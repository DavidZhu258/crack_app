from __future__ import annotations

import json
import os
from pathlib import Path

from fastapi.testclient import TestClient

import server.app.main as main_module
from server.app.main import create_app


def _client(tmp_path, *, auth_disabled: bool = True):
    os.environ["CRACK_SERVER_DATA_DIR"] = str(tmp_path)
    os.environ["CRACK_AUTH_DISABLED"] = "true" if auth_disabled else "false"
    os.environ["CRACK_OIDC_ISSUER"] = "https://id.example.com/realms/jinchuan"
    os.environ["CRACK_OIDC_AUDIENCE"] = "crack-app-api"
    os.environ.pop("CRACK_RECORD_STORE", None)
    os.environ.pop("CRACK_MYSQL_DSN", None)
    return TestClient(create_app())


def test_v1_endpoints_require_bearer_when_auth_enabled(tmp_path):
    client = _client(tmp_path, auth_disabled=False)

    response = client.get("/api/v1/me")

    assert response.status_code == 401
    assert response.json()["detail"] == "missing bearer token"


def test_legacy_password_auth_is_disabled_when_oidc_auth_is_enabled(tmp_path):
    client = _client(tmp_path, auth_disabled=False)

    login = client.post(
        "/auth/login",
        json={"username": "miner01", "password": "password"},
    )
    refresh = client.post("/auth/refresh", json={"refreshToken": "dev-refresh"})

    assert login.status_code == 404
    assert refresh.status_code == 404


def test_v1_auth_config_returns_mobile_oidc_settings(tmp_path, monkeypatch):
    monkeypatch.setenv("CRACK_OIDC_MOBILE_CLIENT_ID", "crack-app-mobile-test")
    monkeypatch.setenv(
        "CRACK_OIDC_MOBILE_REDIRECT_URL",
        "com.jinchuan.crackapp:/oauth2redirect",
    )
    monkeypatch.setenv("CRACK_OIDC_SCOPES", "openid profile email offline_access")
    client = _client(tmp_path, auth_disabled=False)

    response = client.get("/api/v1/auth/config")

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["issuer"] == "https://id.example.com/realms/jinchuan"
    assert data["clientId"] == "crack-app-mobile-test"
    assert data["redirectUrl"] == "com.jinchuan.crackapp:/oauth2redirect"
    assert data["scopes"] == ["openid", "profile", "email", "offline_access"]
    assert data["registrationUrl"].startswith(
        "https://id.example.com/realms/jinchuan/protocol/openid-connect/registrations",
    )
    assert "client_id=crack-app-mobile-test" in data["registrationUrl"]
    assert (
        "redirect_uri=com.jinchuan.crackapp%3A%2Foauth2redirect"
        in data["registrationUrl"]
    )
    assert data["authEnabled"] is True


def test_v1_native_login_returns_keycloak_session(tmp_path, monkeypatch):
    fake = _FakeKeycloakNativeAuthClient()
    monkeypatch.setattr(
        main_module,
        "KeycloakNativeAuthClient",
        lambda: fake,
        raising=False,
    )
    client = _client(tmp_path, auth_disabled=False)

    response = client.post(
        "/api/v1/auth/login",
        json={"username": "miner01", "password": "password"},
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["accessToken"] == "native-access"
    assert data["refreshToken"] == "native-refresh"
    assert data["user"]["username"] == "miner01"
    assert fake.login_calls == [("miner01", "password")]


def test_v1_native_register_creates_account_and_returns_session(tmp_path, monkeypatch):
    fake = _FakeKeycloakNativeAuthClient()
    monkeypatch.setattr(
        main_module,
        "KeycloakNativeAuthClient",
        lambda: fake,
        raising=False,
    )
    client = _client(tmp_path, auth_disabled=False)

    response = client.post(
        "/api/v1/auth/register",
        json={
            "username": "newminer",
            "password": "secret123",
            "displayName": "新矿工",
        },
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["accessToken"] == "registered-access"
    assert data["user"]["username"] == "newminer"
    assert fake.register_calls == [("newminer", "secret123", "新矿工", "")]


def test_v1_native_register_duplicate_username_returns_stable_error(
    tmp_path,
    monkeypatch,
):
    class DuplicateUserClient:
        def register(self, *args, **kwargs):
            raise main_module.HTTPException(
                status_code=409,
                detail="username already exists",
            )

    monkeypatch.setattr(
        main_module,
        "KeycloakNativeAuthClient",
        lambda: DuplicateUserClient(),
        raising=False,
    )
    client = _client(tmp_path, auth_disabled=False)

    response = client.post(
        "/api/v1/auth/register",
        json={"username": "newminer", "password": "secret123"},
    )

    assert response.status_code == 409
    assert response.json()["success"] is False
    assert response.json()["errorCode"] == "USERNAME_EXISTS"
    assert response.json()["message"] == "用户名已存在，请换一个用户名"


def test_v1_guest_auth_returns_operator_session_for_supplied_guest_id(tmp_path):
    client = _client(tmp_path)

    response = client.post(
        "/api/v1/auth/guest",
        json={
            "guestId": "guest_20260513_x7k9",
            "displayName": "访客 x7k9",
        },
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["accessToken"]
    assert data["user"] == {
        "id": "guest_20260513_x7k9",
        "username": "guest_20260513_x7k9",
        "displayName": "访客 x7k9",
        "role": "operator",
    }


def test_keycloak_native_register_resets_password_before_login(monkeypatch):
    calls: list[dict[str, object]] = []

    monkeypatch.setenv("CRACK_OIDC_ISSUER", "http://keycloak:8080/realms/crack")
    monkeypatch.setenv("CRACK_OIDC_MOBILE_CLIENT_ID", "crack-app-mobile")
    monkeypatch.setenv("CRACK_KEYCLOAK_BASE_URL", "http://keycloak:8080")
    monkeypatch.setenv("CRACK_KEYCLOAK_REALM", "crack")
    monkeypatch.setenv("CRACK_KEYCLOAK_ADMIN_USERNAME", "admin")
    monkeypatch.setenv("CRACK_KEYCLOAK_ADMIN_PASSWORD", "admin-password")
    monkeypatch.setattr(
        main_module.httpx,
        "Client",
        lambda timeout: _FakeHttpxClient(calls, timeout),
    )

    session = main_module.KeycloakNativeAuthClient().register(
        "newminer",
        "secret123",
        "新矿工",
    )

    assert session["user"]["username"] == "newminer"
    create_call = next(call for call in calls if call["kind"] == "create_user")
    assert "credentials" not in create_call["json"]
    assert create_call["json"]["email"] == "newminer@users.example.invalid"
    assert create_call["json"]["emailVerified"] is True
    assert create_call["json"]["firstName"] == "新矿工"
    assert create_call["json"]["lastName"] == "newminer"
    reset_call = next(call for call in calls if call["kind"] == "reset_password")
    assert reset_call["json"] == {
        "type": "password",
        "value": "secret123",
        "temporary": False,
    }


def test_v1_me_maps_oidc_claims_in_dev_auth_mode(tmp_path):
    client = _client(tmp_path)

    response = client.get(
        "/api/v1/me",
        headers={
            "X-Dev-User": json.dumps(
                {
                    "sub": "oidc-user-1",
                    "preferred_username": "miner01",
                    "name": "Zhang San",
                    "realm_access": {"roles": ["operator"]},
                },
                ensure_ascii=False,
            )
        },
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["id"] == "oidc-user-1"
    assert data["username"] == "miner01"
    assert data["displayName"] == "Zhang San"
    assert data["role"] == "operator"


class _FakeKeycloakNativeAuthClient:
    def __init__(self) -> None:
        self.login_calls = []
        self.register_calls = []

    def login(self, username: str, password: str) -> dict[str, object]:
        self.login_calls.append((username, password))
        return {
            "accessToken": "native-access",
            "refreshToken": "native-refresh",
            "expiresAt": "2026-05-13T12:00:00Z",
            "user": {
                "id": "native-sub",
                "username": username,
                "displayName": "App 用户",
                "role": "operator",
            },
        }

    def register(
        self,
        username: str,
        password: str,
        display_name: str,
        email: str = "",
    ) -> dict[str, object]:
        self.register_calls.append((username, password, display_name, email))
        return {
            "accessToken": "registered-access",
            "refreshToken": "registered-refresh",
            "expiresAt": "2026-05-13T12:00:00Z",
            "user": {
                "id": "registered-sub",
                "username": username,
                "displayName": display_name,
                "role": "operator",
            },
        }


class _FakeHttpxResponse:
    def __init__(
        self,
        status_code: int,
        body: dict[str, object] | list[dict[str, object]] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        self.status_code = status_code
        self._body = body or {}
        self.headers = headers or {}

    def json(self) -> dict[str, object] | list[dict[str, object]]:
        return self._body


class _FakeHttpxClient:
    def __init__(self, calls: list[dict[str, object]], timeout: int) -> None:
        self.calls = calls
        self.timeout = timeout

    def __enter__(self) -> "_FakeHttpxClient":
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def post(
        self,
        url: str,
        data: dict[str, str] | None = None,
        headers: dict[str, str] | None = None,
        json: dict[str, object] | list[dict[str, object]] | None = None,
    ) -> _FakeHttpxResponse:
        if url.endswith("/realms/master/protocol/openid-connect/token"):
            self.calls.append({"kind": "admin_token", "data": data or {}})
            return _FakeHttpxResponse(200, {"access_token": "admin-access"})
        if url.endswith("/admin/realms/crack/users"):
            self.calls.append({"kind": "create_user", "json": json or {}})
            return _FakeHttpxResponse(
                201,
                headers={
                    "Location": "http://keycloak:8080/admin/realms/crack/users/u-new"
                },
            )
        if url.endswith("/role-mappings/realm"):
            self.calls.append({"kind": "assign_role", "json": json or []})
            return _FakeHttpxResponse(204)
        if url.endswith("/realms/crack/protocol/openid-connect/token"):
            self.calls.append({"kind": "password_login", "data": data or {}})
            return _FakeHttpxResponse(
                200,
                {
                    "access_token": _fake_jwt(
                        {
                            "sub": "u-new",
                            "preferred_username": str((data or {}).get("username")),
                            "name": "新矿工",
                            "realm_access": {"roles": ["operator"]},
                            "exp": 1778652000,
                        }
                    ),
                    "refresh_token": "refresh-token",
                    "expires_in": 300,
                },
            )
        raise AssertionError(f"unexpected POST {url}")

    def put(
        self,
        url: str,
        headers: dict[str, str] | None = None,
        json: dict[str, object] | None = None,
    ) -> _FakeHttpxResponse:
        if url.endswith("/users/u-new/reset-password"):
            self.calls.append({"kind": "reset_password", "json": json or {}})
            return _FakeHttpxResponse(204)
        raise AssertionError(f"unexpected PUT {url}")

    def get(
        self,
        url: str,
        headers: dict[str, str] | None = None,
        params: dict[str, str] | None = None,
    ) -> _FakeHttpxResponse:
        if url.endswith("/admin/realms/crack/roles/operator"):
            self.calls.append({"kind": "get_operator_role"})
            return _FakeHttpxResponse(200, {"id": "role-operator", "name": "operator"})
        raise AssertionError(f"unexpected GET {url}")


def _fake_jwt(payload: dict[str, object]) -> str:
    import base64

    encoded = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode()
    return "header." + encoded.rstrip("=") + ".signature"


def test_v1_me_prefers_app_roles_and_uses_stable_id_fallback(tmp_path):
    client = _client(tmp_path)

    response = client.get(
        "/api/v1/me",
        headers={
            "X-Dev-User": json.dumps(
                {
                    "preferred_username": "miner01",
                    "name": "Smoke Operator",
                    "realm_access": {
                        "roles": [
                            "offline_access",
                            "uma_authorization",
                            "operator",
                        ],
                    },
                },
                ensure_ascii=False,
            )
        },
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["id"] == "miner01"
    assert data["role"] == "operator"


def test_upload_presign_returns_object_storage_metadata(tmp_path):
    client = _client(tmp_path)

    response = client.post(
        "/api/v1/uploads/presign",
        json={
            "recordId": "r1",
            "metadata": {
                "timestamp": "2026-05-13T08:00:00Z",
                "engineeringInfo": {
                    "workerName": "张三",
                    "projectLocation": "二矿598",
                    "projectName": "水泵房",
                },
            },
            "assets": [
                {
                    "kind": "originalImage",
                    "fileName": "face.jpg",
                    "contentType": "image/jpeg",
                    "sha256": "abc123",
                    "sizeBytes": 4,
                }
            ],
        },
    )

    assert response.status_code == 200
    upload = response.json()["data"]["uploads"][0]
    assert upload["bucket"]
    expected_base = (
        "dev-user_Developer_张三_水泵房_二矿598_20260513T080000Z"
    )
    assert upload["objectKey"].startswith(
        f"records/{expected_base}/r1/originalImage/{expected_base}_r1_originalImage_"
    )
    assert upload["objectKey"].endswith("_face.jpg")
    assert upload["uploadUrl"].startswith("http")
    assert upload["headers"]["Content-Type"] == "image/jpeg"


def test_upload_presign_uses_readable_fallbacks_for_missing_report_fields(tmp_path):
    client = _client(tmp_path)

    response = client.post(
        "/api/v1/uploads/presign",
        json={
            "recordId": "r-missing",
            "metadata": {"timestamp": "2026-05-13T08:00:00Z"},
            "assets": [
                {
                    "kind": "report",
                    "fileName": "report.txt",
                    "contentType": "text/plain",
                }
            ],
        },
    )

    assert response.status_code == 200
    object_key = response.json()["data"]["uploads"][0]["objectKey"]
    assert "None" not in object_key
    assert object_key.startswith(
        "records/dev-user_Developer_未填报告人_未填项目_未填地点_"
        "20260513T080000Z/r-missing/report/"
    )


def test_upload_presign_trims_repeated_username_from_display_name(tmp_path):
    client = _client(tmp_path)
    dev_user = {
        "sub": "guest_20260514_x7k9",
        "preferred_username": "guest_20260514_x7k9",
        "name": "访客 x7k9 guest_20260514_x7k9",
        "realm_access": {"roles": ["operator"]},
    }

    response = client.post(
        "/api/v1/uploads/presign",
        headers={"X-Dev-User": json.dumps(dev_user)},
        json={
            "recordId": "r-guest",
            "metadata": {
                "timestamp": "2026-05-14T03:21:00Z",
                "engineeringInfo": {
                    "workerName": "李四",
                    "projectName": "主运输巷",
                    "projectLocation": "三矿900",
                },
            },
            "assets": [
                {
                    "kind": "report",
                    "fileName": "report.txt",
                    "contentType": "text/plain",
                }
            ],
        },
    )

    assert response.status_code == 200
    object_key = response.json()["data"]["uploads"][0]["objectKey"]
    assert "访客_x7k9_guest_20260514_x7k9" not in object_key
    assert object_key.startswith(
        "records/guest_20260514_x7k9_访客_x7k9_李四_主运输巷_"
        "三矿900_20260514T032100Z/r-guest/report/"
    )


def test_v1_record_sync_persists_assets_formula_and_manual_review(tmp_path):
    client = _client(tmp_path)
    payload = {
        "id": "r1",
        "timestamp": "2026-05-07T09:00:00.000Z",
        "engineeringInfo": {
            "rockType": "granite",
            "elevation": 598,
            "projectLocation": "二矿598",
            "projectName": "水泵房",
            "workerName": "张三",
            "hasSeepage": False,
        },
        "indicators": {
            "indicator1": 1.6702,
            "indicator2": 49.92,
            "indicator3": 1.4333,
        },
        "formulaSnapshot": {
            "scores": {
                "JCI": "20.314887",
                "RMR": "22.000000",
            }
        },
        "classification": {"finalGrade": "III"},
        "supportPlan": {"summary": "算法匹配 III 支护"},
        "assets": [
            {
                "kind": "originalImage",
                "objectKey": "records/r1/originalImage/face.jpg",
                "sha256": "abc123",
                "contentType": "image/jpeg",
                "sizeBytes": 4,
                "width": 1024,
                "height": 768,
            }
        ],
        "manualReview": {
            "acceptedRecognitionResult": False,
            "manualGrade": "IV",
            "selectedSupportPlan": {"summary": "人工 IV 类支护"},
            "reviewerName": "王工",
            "note": "人工复核调整",
            "reviewedAt": "2026-05-07T09:30:00.000Z",
        },
    }

    response = client.post(
        "/api/v1/records/sync",
        json=payload,
        headers={"Idempotency-Key": "r1_v2"},
    )
    duplicate = client.post(
        "/api/v1/records/sync",
        json=payload,
        headers={"Idempotency-Key": "r1_v2"},
    )

    assert response.status_code == 200
    assert duplicate.status_code == 200
    assert (
        response.json()["data"]["remoteRecordId"]
        == duplicate.json()["data"]["remoteRecordId"]
    )

    records = client.get("/api/v1/records").json()["data"]["records"]
    record = records[0]["record"]
    assert record["assets"][0]["objectKey"] == "records/r1/originalImage/face.jpg"
    assert record["formulaSnapshot"]["scores"]["JCI"] == "20.314887"
    assert record["manualReview"]["manualGrade"] == "IV"


def test_v1_admin_reports_lists_report_download_urls(tmp_path):
    client = _client(tmp_path)
    record = {
        "id": "report-r1",
        "timestamp": "2026-05-13T09:00:00.000Z",
        "operatorUserId": "dev-user",
        "engineeringInfo": {
            "projectName": "水泵房",
            "rockType": "granite",
            "elevation": 598,
        },
        "assets": [
            {
                "kind": "report",
                "bucket": "crack-record-assets",
                "objectKey": "records/report-r1/report/report.txt",
                "contentType": "text/plain",
                "sizeBytes": 42,
            }
        ],
    }
    sync = client.post(
        "/api/v1/records/sync",
        json=record,
        headers={"Idempotency-Key": "report-r1-v1"},
    )

    response = client.get("/api/v1/admin/reports")

    assert sync.status_code == 200
    assert response.status_code == 200
    reports = response.json()["data"]["reports"]
    assert reports == [
        {
            "userId": "dev-user",
            "username": "dev",
            "displayName": "Developer",
            "remoteRecordId": "cloud_report-r1",
            "timestamp": "2026-05-13T09:00:00.000Z",
            "projectName": "水泵房",
            "downloadUrl": (
                "http://localhost:9000/crack-record-assets/"
                "records/report-r1/report/report.txt"
            ),
        }
    ]


def test_manual_review_endpoint_updates_existing_record(tmp_path):
    client = _client(tmp_path)
    sync = client.post(
        "/api/v1/records/sync",
        json={"id": "r2", "timestamp": "2026-05-07T09:00:00.000Z"},
        headers={"Idempotency-Key": "r2_v1"},
    )
    remote_id = sync.json()["data"]["remoteRecordId"]

    response = client.post(
        f"/api/v1/records/{remote_id}/manual-review",
        json={
            "acceptedRecognitionResult": True,
            "reviewerName": "李工",
            "note": "认可",
            "reviewedAt": "2026-05-07T10:00:00.000Z",
        },
    )

    assert response.status_code == 200
    record = client.get(f"/api/v1/records/{remote_id}").json()["data"]["record"]
    assert record["manualReview"]["acceptedRecognitionResult"] is True
    assert record["manualReview"]["reviewerName"] == "李工"


def test_manual_review_endpoint_uses_configured_record_store(tmp_path, monkeypatch):
    client = _client(tmp_path)
    calls = []

    class FakeStore:
        def update_manual_review(
            self,
            remote_record_id,
            manual_review,
            *,
            reviewer_user_id,
        ):
            calls.append(
                {
                    "remoteRecordId": remote_record_id,
                    "manualReview": manual_review,
                    "reviewerUserId": reviewer_user_id,
                },
            )
            return {
                "remoteRecordId": remote_record_id,
                "syncedAt": "2026-05-07T10:00:00Z",
                "record": {
                    "id": "r3",
                    "remoteRecordId": remote_record_id,
                    "manualReview": manual_review,
                },
            }

    monkeypatch.setattr("server.app.main.MySqlRecordStore", lambda: FakeStore())
    os.environ["CRACK_RECORD_STORE"] = "mysql"
    try:
        response = client.post(
            "/api/v1/records/cloud_r3/manual-review",
            json={
                "acceptedRecognitionResult": False,
                "manualGrade": "IV",
                "reviewerName": "李工",
            },
        )
    finally:
        os.environ.pop("CRACK_RECORD_STORE", None)

    assert response.status_code == 200
    assert calls == [
        {
            "remoteRecordId": "cloud_r3",
            "manualReview": {
                "acceptedRecognitionResult": False,
                "manualGrade": "IV",
                "reviewerName": "李工",
            },
            "reviewerUserId": "dev-user",
        }
    ]


def test_mask_compare_accepts_app_mask_and_reports_exact_match(tmp_path):
    client = _client(tmp_path)
    inference = client.post(
        "/api/v1/inference/crack",
        data={"threshold": "0.3", "maxWindows": "20"},
        files={"image": ("face.jpg", b"\x00\xff\x80\x10", "image/jpeg")},
    )
    assert inference.status_code == 200
    app_mask = inference.json()["data"]["binaryMask"]

    response = client.post(
        "/api/v1/diagnostics/mask-compare",
        data={
            "appMask": json.dumps({"binaryMask": app_mask}),
            "threshold": "0.3",
            "maxWindows": "20",
        },
        files={"image": ("face.jpg", b"\x00\xff\x80\x10", "image/jpeg")},
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["passed"] is True
    assert data["failedReasons"] == []
    assert data["metrics"]["maskIou"] == 1.0
    assert data["metrics"]["pixelErrorRate"] == 0.0
    assert data["server"]["binaryMask"] == app_mask


def test_mask_compare_accepts_rle_app_mask_file(tmp_path):
    client = _client(tmp_path)
    mask_payload = {
        "binaryMaskRle": {
            "width": 4,
            "height": 2,
            "firstValue": False,
            "runs": [1, 2, 3, 1, 1],
        }
    }

    response = client.post(
        "/api/v1/diagnostics/mask-compare",
        data={"includeServerMask": "false"},
        files={
            "image": ("face.jpg", b"\x00\xff\x80\x10", "image/jpeg"),
            "appMaskFile": (
                "app_binary_mask.json",
                json.dumps(mask_payload).encode("utf-8"),
                "application/json",
            ),
        },
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["dimensions"]["app"] == {"width": 4, "height": 2}
    assert "binaryMask" not in data["server"]


def test_mask_compare_rejects_invalid_app_mask(tmp_path):
    client = _client(tmp_path)

    response = client.post(
        "/api/v1/diagnostics/mask-compare",
        data={"appMask": "not-json"},
        files={"image": ("face.jpg", b"\x00\xff\x80\x10", "image/jpeg")},
    )

    assert response.status_code == 400
    assert "appMask" in response.json()["detail"]


def test_python_formula_snapshot_matches_shared_golden_cases():
    from server.app.jci_formula import JciFormulaCalculator

    fixture_path = (
        Path(__file__).resolve().parents[2]
        / "test"
        / "fixtures"
        / "jci_formula_cases.json"
    )
    cases = json.loads(fixture_path.read_text(encoding="utf-8"))["cases"]
    calculator = JciFormulaCalculator()

    for entry in cases:
        assert calculator.canonical_snapshot(entry["input"]) == entry["expected"]
