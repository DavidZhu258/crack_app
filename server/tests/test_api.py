from __future__ import annotations

import os

from fastapi.testclient import TestClient

from server.app.main import create_app


def _client(tmp_path):
    os.environ["CRACK_SERVER_DATA_DIR"] = str(tmp_path)
    os.environ["CRACK_AUTH_DISABLED"] = "true"
    os.environ.pop("CRACK_ENABLE_LEGACY_AUTH", None)
    return TestClient(create_app())


def test_login_and_health(tmp_path):
    client = _client(tmp_path)

    health = client.get("/health")
    assert health.status_code == 200
    assert health.json()["data"]["status"] == "ready"

    response = client.post(
        "/auth/login",
        json={"username": "miner01", "password": "password"},
    )
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["accessToken"]
    assert data["user"]["username"] == "miner01"


def test_crack_inference_contract(tmp_path):
    client = _client(tmp_path)

    response = client.post(
        "/inference/crack",
        data={"threshold": "0.3", "maxWindows": "20"},
        files={"image": ("face.jpg", b"\x00\xff\x80\x10", "image/jpeg")},
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["crackRatio"] >= 0
    assert data["detectionCount"] >= 1
    assert data["resultImage"]
    assert data["binaryMask"]
    assert data["modelVersion"].startswith("savss_256")


def test_record_sync_is_idempotent_and_keeps_manual_review_for_download(tmp_path):
    client = _client(tmp_path)
    payload = {
        "id": "r1",
        "timestamp": "2026-05-07T09:00:00.000Z",
        "image1Path": "/tmp/face.jpg",
        "image2Path": "/tmp/face.jpg",
        "resultImage1": "AQID",
        "resultImage2": "AQID",
        "extractedParams": {
            "rqd": 80,
            "jointSpacing": 20,
            "jointDensity": 1,
            "resultImage1": "AQID",
            "resultImage2": "AQID",
        },
        "engineeringInfo": {
            "rockType": "granite",
            "depth": 598,
            "elevation": 598,
            "waterCondition": "dry",
            "location": "二矿598",
            "projectName": "水泵房",
            "inspector": "张三",
            "hasSeepage": False,
        },
        "jciResult": {"jciValue": 35, "componentScores": {}},
        "classification": {
            "originalGrade": "ii1",
            "finalGrade": "ii1",
            "wasDowngraded": False,
        },
        "supportPlan": {
            "grade": "ii1",
            "methods": [],
            "summary": "算法匹配 II-1 支护",
            "isPlaceholder": False,
        },
        "manualReview": {
            "acceptedRecognitionResult": False,
            "manualGrade": "iv",
            "selectedSupportPlan": {
                "grade": "iv",
                "methods": [],
                "summary": "人工 IV 类支护",
                "isPlaceholder": False,
            },
            "reviewerName": "王工",
            "note": "人工复核调整",
            "reviewedAt": "2026-05-07T09:30:00.000Z",
        },
        "syncStatus": "pendingUpload",
        "updatedAt": "2026-05-07T09:30:00.000Z",
    }

    first = client.post(
        "/records/sync",
        json=payload,
        headers={"Idempotency-Key": "r1_v1"},
    )
    second = client.post(
        "/records/sync",
        json=payload,
        headers={"Idempotency-Key": "r1_v1"},
    )

    assert first.status_code == 200
    assert second.status_code == 200
    assert (
        first.json()["data"]["remoteRecordId"]
        == second.json()["data"]["remoteRecordId"]
    )

    records = client.get("/records").json()["data"]["records"]
    assert len(records) == 1
    assert records[0]["record"]["manualReview"]["manualGrade"] == "iv"

    remote_id = first.json()["data"]["remoteRecordId"]
    downloaded = client.get(f"/records/{remote_id}")
    assert downloaded.status_code == 200
    assert downloaded.json()["data"]["record"]["manualReview"]["reviewerName"] == "王工"
