from __future__ import annotations

import hashlib
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import httpx


def main() -> None:
    config = _config()
    image_bytes, image_name = _image_bytes()
    record_id = f"live_{uuid4().hex}"
    idempotency_key = f"{record_id}:idem"
    with httpx.Client(timeout=config["timeout"]) as client:
        token = _access_token(client, config)
        _progress("token")
        headers = {"Authorization": f"Bearer {token}"}

        me = _data(client.get(f"{config['api_base']}/api/v1/me", headers=headers))
        _progress("me")
        uploads = _presign_and_upload(
            client,
            config,
            headers,
            image_bytes,
            record_id,
        )
        _progress("uploads")
        remote_record_id = _sync_record(
            client,
            config,
            headers,
            uploads,
            image_name,
            record_id=record_id,
            idempotency_key=idempotency_key,
        )
        _progress("record_sync")
        duplicate_remote_record_id = _sync_record(
            client,
            config,
            headers,
            uploads,
            image_name,
            record_id=record_id,
            idempotency_key=idempotency_key,
        )
        _progress("record_sync_duplicate")
        manual_review = _manual_review(client, config, headers, remote_record_id)
        _progress("manual_review")
        downloaded = _data(
            client.get(
                f"{config['api_base']}/api/v1/records/{remote_record_id}",
                headers=headers,
            ),
        )
        _progress("record_download")
        mask_compare = _mask_compare(client, config, headers, image_bytes, image_name)
        _progress("mask_compare")

    if duplicate_remote_record_id != remote_record_id:
        raise RuntimeError("idempotent record sync returned a different remote id")
    if not mask_compare["passed"]:
        raise RuntimeError(f"mask compare failed: {mask_compare['failedReasons']}")
    if downloaded["record"]["manualReview"]["reviewerName"] != "live-smoke":
        raise RuntimeError("manual review was not persisted")

    print(
        json.dumps(
            {
                "me": me,
                "remoteRecordId": remote_record_id,
                "uploadedAssetKinds": sorted(item["kind"] for item in uploads),
                "manualReview": manual_review,
                "maskCompare": {
                    "passed": mask_compare["passed"],
                    "metrics": mask_compare["metrics"],
                    "server": {
                        "inferenceBackend": mask_compare["server"]["inferenceBackend"],
                        "modelVersion": mask_compare["server"]["modelVersion"],
                        "detectionCount": mask_compare["server"]["detectionCount"],
                    },
                },
            },
            ensure_ascii=False,
            indent=2,
        ),
    )


def _config() -> dict[str, object]:
    username = os.environ.get("CRACK_KEYCLOAK_TEST_USER", "miner01")
    password = os.environ.get("CRACK_KEYCLOAK_TEST_PASSWORD", "")
    if not password:
        raise RuntimeError("CRACK_KEYCLOAK_TEST_PASSWORD is required")
    return {
        "api_base": os.environ.get("CRACK_LIVE_API_BASE", "http://127.0.0.1:8000").rstrip("/"),
        "token_url": os.environ.get(
            "CRACK_KEYCLOAK_TOKEN_URL",
            "http://127.0.0.1:8080/realms/crack/protocol/openid-connect/token",
        ),
        "client_id": os.environ.get("CRACK_KEYCLOAK_CLIENT_ID", "crack-app-mobile"),
        "username": username,
        "password": password,
        "timeout": float(os.environ.get("CRACK_LIVE_TIMEOUT_SECONDS", "900")),
    }


def _access_token(client: httpx.Client, config: dict[str, object]) -> str:
    response = client.post(
        str(config["token_url"]),
        data={
            "grant_type": "password",
            "client_id": config["client_id"],
            "username": config["username"],
            "password": config["password"],
            "scope": "openid profile email offline_access",
        },
    )
    if response.status_code >= 400:
        raise RuntimeError(
            f"Keycloak token request failed {response.status_code}: {response.text}",
        )
    token = response.json().get("access_token")
    if not token:
        raise RuntimeError("Keycloak token response did not include access_token")
    return str(token)


def _presign_and_upload(
    client: httpx.Client,
    config: dict[str, object],
    headers: dict[str, str],
    image_bytes: bytes,
    record_id: str,
) -> list[dict[str, object]]:
    mask_bytes = json.dumps(
        {"binaryMask": [[True, False], [False, True]]},
        separators=(",", ":"),
    ).encode("utf-8")
    report_bytes = b"live smoke report\n"
    asset_payloads = {
        "originalImage": ("face.jpg", "image/jpeg", image_bytes),
        "mask": ("mask.json", "application/json", mask_bytes),
        "report": ("report.txt", "text/plain", report_bytes),
    }
    response = client.post(
        f"{config['api_base']}/api/v1/uploads/presign",
        headers=headers,
        json={
            "recordId": record_id,
            "assets": [
                {
                    "kind": kind,
                    "fileName": file_name,
                    "contentType": content_type,
                    "sha256": _sha256(content),
                    "sizeBytes": len(content),
                }
                for kind, (file_name, content_type, content) in asset_payloads.items()
            ],
        },
    )
    uploads = _data(response)["uploads"]
    for upload in uploads:
        kind = upload["kind"]
        _, _, content = asset_payloads[kind]
        put_headers = {str(k): str(v) for k, v in upload.get("headers", {}).items()}
        put = client.put(str(upload["uploadUrl"]), headers=put_headers, content=content)
        put.raise_for_status()
        upload["sha256"] = _sha256(content)
        upload["sizeBytes"] = len(content)
    return uploads


def _sync_record(
    client: httpx.Client,
    config: dict[str, object],
    headers: dict[str, str],
    uploads: list[dict[str, object]],
    image_name: str,
    *,
    record_id: str,
    idempotency_key: str,
) -> str:
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    response = client.post(
        f"{config['api_base']}/api/v1/records/sync",
        headers={**headers, "Idempotency-Key": idempotency_key},
        json={
            "id": record_id,
            "timestamp": now,
            "image1Path": image_name,
            "engineeringInfo": {
                "rockType": "granite",
                "projectLocation": "live-smoke",
                "projectName": "remote-minimal-integration",
                "workerName": "live-smoke",
                "elevation": 598,
                "hasSeepage": False,
            },
            "indicators": {
                "indicator1": 1.67,
                "indicator2": 49.92,
                "indicator3": 1.43,
            },
            "formulaSnapshot": {
                "scores": {
                    "JCI": "20.314887",
                    "RMR": "22.000000",
                    "Q": "4.000000",
                }
            },
            "classification": {"finalGrade": "III"},
            "supportPlan": {"summary": "live smoke support plan"},
            "manualReview": {
                "acceptedRecognitionResult": False,
                "manualGrade": "IV",
                "selectedSupportPlan": {"summary": "manual smoke support plan"},
                "reviewerName": "live-smoke",
                "note": "created by live smoke",
                "reviewedAt": now,
            },
            "assets": [
                {
                    "kind": upload["kind"],
                    "bucket": upload["bucket"],
                    "objectKey": upload["objectKey"],
                    "sha256": upload.get("sha256"),
                    "contentType": upload.get("headers", {}).get(
                        "Content-Type",
                        "application/octet-stream",
                    ),
                    "sizeBytes": upload.get("sizeBytes"),
                }
                for upload in uploads
            ],
        },
    )
    return str(_data(response)["remoteRecordId"])


def _manual_review(
    client: httpx.Client,
    config: dict[str, object],
    headers: dict[str, str],
    remote_record_id: str,
) -> dict[str, object]:
    payload = {
        "acceptedRecognitionResult": True,
        "reviewerName": "live-smoke",
        "note": "accepted after smoke review",
        "reviewedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    response = client.post(
        f"{config['api_base']}/api/v1/records/{remote_record_id}/manual-review",
        headers=headers,
        json=payload,
    )
    _data(response)
    return payload


def _mask_compare(
    client: httpx.Client,
    config: dict[str, object],
    headers: dict[str, str],
    image_bytes: bytes,
    image_name: str,
) -> dict[str, object]:
    inference = client.post(
        f"{config['api_base']}/api/v1/inference/crack",
        headers=headers,
        data={"threshold": "0.3", "maxWindows": "20"},
        files={"image": (image_name, image_bytes, "image/jpeg")},
    )
    app_mask = _data(inference)["binaryMask"]
    response = client.post(
        f"{config['api_base']}/api/v1/diagnostics/mask-compare",
        headers=headers,
        data={
            "appMask": json.dumps({"binaryMask": app_mask}, separators=(",", ":")),
            "threshold": "0.3",
            "maxWindows": "20",
        },
        files={"image": (image_name, image_bytes, "image/jpeg")},
    )
    return _data(response)


def _image_bytes() -> tuple[bytes, str]:
    image_path = os.environ.get("CRACK_LIVE_IMAGE_PATH")
    if image_path:
        path = Path(image_path)
        return path.read_bytes(), path.name
    try:
        from PIL import Image
    except ImportError as exc:
        raise RuntimeError("Pillow is required when CRACK_LIVE_IMAGE_PATH is unset") from exc
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as handle:
        temp_path = Path(handle.name)
    try:
        image = Image.new("RGB", (64, 64), (32, 32, 32))
        for index in range(64):
            image.putpixel((index, index), (240, 240, 240))
        image.save(temp_path, format="JPEG")
        return temp_path.read_bytes(), "generated-smoke.jpg"
    finally:
        temp_path.unlink(missing_ok=True)


def _data(response: httpx.Response) -> dict[str, object]:
    if response.status_code >= 400:
        raise RuntimeError(
            f"API request failed {response.status_code} for "
            f"{response.request.method} {response.request.url}: {response.text[:2000]}",
        )
    response.raise_for_status()
    body = response.json()
    if not body.get("success"):
        raise RuntimeError(f"API returned success=false: {body}")
    data = body.get("data")
    if not isinstance(data, dict):
        raise RuntimeError(f"API response did not include object data: {body}")
    return data


def _sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def _progress(step: str) -> None:
    print(f"[OK] {step}", flush=True)


if __name__ == "__main__":
    main()
