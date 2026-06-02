from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

import httpx


def main() -> None:
    args = _parse_args()
    token = _access_token(args)
    with httpx.Client(timeout=args.timeout) as client:
        with Path(args.image_path).open("rb") as image_handle:
            with Path(args.mask_path).open("rb") as mask_handle:
                response = client.post(
                    f"{args.api_base.rstrip('/')}/api/v1/diagnostics/mask-compare",
                    headers={"Authorization": f"Bearer {token}"},
                    data={
                        "threshold": str(args.threshold),
                        "maxWindows": str(args.max_windows),
                        "includeServerMask": "true" if args.include_server_mask else "false",
                    },
                    files={
                        "image": (
                            Path(args.image_path).name,
                            image_handle,
                            args.image_content_type,
                        ),
                        "appMaskFile": (
                            Path(args.mask_path).name,
                            mask_handle,
                            "application/json",
                        ),
                    },
                )
    data = _unwrap(response)
    print(
        json.dumps(
            {
                "passed": data["passed"],
                "failedReasons": data["failedReasons"],
                "metrics": data["metrics"],
                "dimensions": data["dimensions"],
                "server": {
                    "inferenceBackend": data["server"].get("inferenceBackend"),
                    "modelVersion": data["server"].get("modelVersion"),
                    "detectionCount": data["server"].get("detectionCount"),
                    "crackRatio": data["server"].get("crackRatio"),
                },
            },
            ensure_ascii=False,
            indent=2,
        ),
    )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare an app-exported binary mask with server crackscan output.",
    )
    parser.add_argument("--image-path", required=True)
    parser.add_argument("--mask-path", required=True)
    parser.add_argument(
        "--api-base",
        default=os.environ.get("CRACK_LIVE_API_BASE", "http://127.0.0.1:8000"),
    )
    parser.add_argument(
        "--token-url",
        default=os.environ.get(
            "CRACK_KEYCLOAK_TOKEN_URL",
            "http://127.0.0.1:8080/realms/crack/protocol/openid-connect/token",
        ),
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("CRACK_KEYCLOAK_CLIENT_ID", "crack-app-mobile"),
    )
    parser.add_argument(
        "--username",
        default=os.environ.get("CRACK_KEYCLOAK_TEST_USER", "miner01"),
    )
    parser.add_argument(
        "--password",
        default=os.environ.get("CRACK_KEYCLOAK_TEST_PASSWORD", ""),
    )
    parser.add_argument("--threshold", type=float, default=0.3)
    parser.add_argument("--max-windows", type=int, default=20)
    parser.add_argument("--timeout", type=float, default=900)
    parser.add_argument("--image-content-type", default="image/jpeg")
    parser.add_argument("--include-server-mask", action="store_true")
    return parser.parse_args()


def _access_token(args: argparse.Namespace) -> str:
    if not args.password:
        raise RuntimeError("CRACK_KEYCLOAK_TEST_PASSWORD or --password is required")
    with httpx.Client(timeout=args.timeout) as client:
        response = client.post(
            args.token_url,
            data={
                "grant_type": "password",
                "client_id": args.client_id,
                "username": args.username,
                "password": args.password,
                "scope": "openid profile email offline_access",
            },
        )
    body = _json_body(response)
    token = body.get("access_token")
    if not token:
        raise RuntimeError("Keycloak token response did not include access_token")
    return str(token)


def _unwrap(response: httpx.Response) -> dict[str, Any]:
    body = _json_body(response)
    if response.status_code >= 400:
        raise RuntimeError(
            f"API request failed {response.status_code}: {response.text[:2000]}",
        )
    if body.get("success") is False:
        raise RuntimeError(f"API returned success=false: {body}")
    data = body.get("data")
    if not isinstance(data, dict):
        raise RuntimeError(f"API response did not include data object: {body}")
    return data


def _json_body(response: httpx.Response) -> dict[str, Any]:
    if response.status_code >= 400:
        raise RuntimeError(
            f"Request failed {response.status_code}: {response.text[:2000]}",
        )
    body = response.json()
    if not isinstance(body, dict):
        raise RuntimeError(f"Response was not a JSON object: {body}")
    return body


if __name__ == "__main__":
    main()
