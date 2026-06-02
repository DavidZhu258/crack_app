from __future__ import annotations

import json
import os
import re
import base64
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlencode
from uuid import uuid4

import httpx
from fastapi import (
    Body,
    Depends,
    FastAPI,
    File,
    Form,
    Header,
    HTTPException,
    UploadFile,
)
from fastapi.responses import JSONResponse
from server.app.inference import InferenceError, run_inference
from server.app.mask_compare import compare_masks, parse_mask_json
from server.app.mysql_store import MySqlRecordStore

SERVER_VERSION = "mvp-1.0.0"
MODEL_VERSION = "savss_256_server"
UTC = timezone.utc
APP_ROLE_PRIORITY = ("admin", "reviewer", "operator")


def create_app() -> FastAPI:
    app = FastAPI(title="Crack App Server", version=SERVER_VERSION)

    @app.get("/health")
    def health() -> dict[str, Any]:
        return _ok(
            {
                "serverVersion": SERVER_VERSION,
                "modelVersion": MODEL_VERSION,
                "status": "ready",
            },
            request_id="req_health",
        )

    @app.post("/auth/login")
    def login(payload: dict[str, Any] = Body(...)) -> dict[str, Any]:
        if not _legacy_auth_enabled():
            raise HTTPException(status_code=404, detail="legacy auth is disabled")
        username = str(payload.get("username", "")).strip()
        password = str(payload.get("password", ""))
        if username != "miner01" or password != "password":
            raise HTTPException(status_code=401, detail="invalid credentials")
        return _ok(_session(username))

    @app.post("/auth/refresh")
    def refresh(payload: dict[str, Any] = Body(...)) -> dict[str, Any]:
        if not _legacy_auth_enabled():
            raise HTTPException(status_code=404, detail="legacy auth is disabled")
        refresh_token = str(payload.get("refreshToken", "")).strip()
        if not refresh_token:
            raise HTTPException(status_code=401, detail="missing refresh token")
        return _ok(_session("miner01"))

    @app.post("/inference/crack")
    async def infer_crack(
        image: UploadFile = File(...),
        threshold: float = Form(0.3),
        max_windows: int = Form(20, alias="maxWindows"),
    ) -> dict[str, Any]:
        raw = await image.read()
        data = _infer(raw, threshold=threshold, max_windows=max_windows)
        return _ok(data)

    @app.get("/api/v1/auth/config")
    def auth_config() -> dict[str, Any]:
        return _ok(_mobile_oidc_config())

    @app.post("/api/v1/auth/login")
    def native_login(payload: dict[str, Any] = Body(...)) -> dict[str, Any]:
        username = str(payload.get("username", "")).strip()
        password = str(payload.get("password", ""))
        if not username or not password:
            raise HTTPException(
                status_code=400, detail="username and password are required"
            )
        if _auth_disabled():
            return _ok(_session(username))
        return _ok(KeycloakNativeAuthClient().login(username, password))

    @app.post("/api/v1/auth/register")
    def native_register(payload: dict[str, Any] = Body(...)) -> dict[str, Any]:
        username = str(payload.get("username", "")).strip()
        password = str(payload.get("password", ""))
        display_name = str(payload.get("displayName") or username).strip()
        email = str(payload.get("email") or "").strip()
        if not username or not password:
            raise HTTPException(
                status_code=400, detail="username and password are required"
            )
        if len(password) < 6:
            raise HTTPException(
                status_code=400, detail="password must be at least 6 characters"
            )
        if _auth_disabled():
            return _ok(_session(username))
        try:
            return _ok(
                KeycloakNativeAuthClient().register(
                    username,
                    password,
                    display_name,
                    email,
                )
            )
        except HTTPException as exc:
            if exc.status_code == 409:
                return _error(
                    409,
                    "USERNAME_EXISTS",
                    "用户名已存在，请换一个用户名",
                )
            raise

    @app.post("/api/v1/auth/guest")
    def guest_auth(payload: dict[str, Any] = Body(default={})) -> dict[str, Any]:
        guest_id = _guest_id(str(payload.get("guestId") or ""))
        display_name = str(payload.get("displayName") or "").strip()
        if not display_name:
            display_name = _guest_display_name(guest_id)
        user = {
            "id": guest_id,
            "username": guest_id,
            "displayName": display_name,
            "role": "operator",
        }
        if _auth_disabled():
            _upsert_user_snapshot(user)
            return _ok(_session_for_user(user))
        return _ok(KeycloakNativeAuthClient().guest(guest_id, display_name))

    @app.post("/api/v1/auth/refresh")
    def native_refresh(payload: dict[str, Any] = Body(...)) -> dict[str, Any]:
        refresh_token = str(payload.get("refreshToken", "")).strip()
        if not refresh_token:
            raise HTTPException(status_code=400, detail="refreshToken is required")
        if _auth_disabled():
            return _ok(_session("dev"))
        return _ok(KeycloakNativeAuthClient().refresh(refresh_token))

    @app.post("/api/v1/inference/crack")
    async def infer_crack_v1(
        image: UploadFile = File(...),
        threshold: float = Form(0.3),
        max_windows: int = Form(20, alias="maxWindows"),
        user: dict[str, Any] = Depends(_current_user),
    ) -> dict[str, Any]:
        raw = await image.read()
        data = _infer(raw, threshold=threshold, max_windows=max_windows)
        data["operatorUserId"] = user["id"]
        return _ok(data)

    @app.get("/api/v1/me")
    def me(user: dict[str, Any] = Depends(_current_user)) -> dict[str, Any]:
        _upsert_user_snapshot(user)
        return _ok(user)

    @app.post("/api/v1/uploads/presign")
    def presign_uploads(
        payload: dict[str, Any] = Body(...),
        user: dict[str, Any] = Depends(_current_user),
    ) -> dict[str, Any]:
        presigner = ObjectStoragePresigner()
        metadata = payload.get("metadata")
        uploads = presigner.presign_uploads(
            record_id=str(payload.get("recordId") or uuid4().hex),
            assets=payload.get("assets") or [],
            user=user,
            metadata=metadata if isinstance(metadata, dict) else {},
        )
        return _ok({"uploads": uploads})

    @app.post("/records/sync")
    def sync_record(
        payload: dict[str, Any] = Body(...),
        idempotency_key: str | None = Header(
            default=None,
            alias="Idempotency-Key",
        ),
    ) -> dict[str, Any]:
        if not idempotency_key:
            raise HTTPException(status_code=400, detail="missing Idempotency-Key")
        store = _record_store()
        snapshot = store.sync_record(payload, idempotency_key)
        return _ok(
            {
                "remoteRecordId": snapshot["remoteRecordId"],
                "syncedAt": snapshot["syncedAt"],
            },
        )

    @app.post("/api/v1/records/sync")
    def sync_record_v1(
        payload: dict[str, Any] = Body(...),
        idempotency_key: str | None = Header(
            default=None,
            alias="Idempotency-Key",
        ),
        user: dict[str, Any] = Depends(_current_user),
    ) -> dict[str, Any]:
        if not idempotency_key:
            raise HTTPException(status_code=400, detail="missing Idempotency-Key")
        store = _record_store()
        _upsert_user_snapshot(user)
        enriched = {
            **payload,
            "operatorUserId": payload.get("operatorUserId") or user["id"],
        }
        try:
            snapshot = store.sync_record(enriched, idempotency_key)
        except Exception as exc:  # noqa: BLE001 - keep API response structured
            return _error(
                500,
                "RECORD_SYNC_FAILED",
                "服务器同步失败",
                detail=str(exc),
            )
        return _ok(
            {
                "remoteRecordId": snapshot["remoteRecordId"],
                "syncedAt": snapshot["syncedAt"],
            },
        )

    @app.get("/records")
    def list_records() -> dict[str, Any]:
        store = _record_store()
        return _ok({"records": store.list_records()})

    @app.get("/api/v1/records")
    def list_records_v1(
        user: dict[str, Any] = Depends(_current_user),
    ) -> dict[str, Any]:
        store = _record_store()
        records = store.list_records(owner_id=user["id"])
        return _ok({"records": records})

    @app.get("/api/v1/admin/reports")
    def list_admin_reports(
        user: dict[str, Any] = Depends(_current_user),
    ) -> dict[str, Any]:
        store = _record_store()
        owner_id = None if user.get("role") in {"admin", "reviewer"} else user["id"]
        reports = store.list_reports(
            owner_id=owner_id,
            presigner=ObjectStoragePresigner(),
        )
        return _ok({"reports": reports})

    @app.get("/records/{remote_record_id}")
    def get_record(remote_record_id: str) -> dict[str, Any]:
        store = _record_store()
        snapshot = store.get_record(remote_record_id)
        if snapshot is None:
            raise HTTPException(status_code=404, detail="record not found")
        return _ok(snapshot)

    @app.get("/api/v1/records/{remote_record_id}")
    def get_record_v1(
        remote_record_id: str,
        user: dict[str, Any] = Depends(_current_user),
    ) -> dict[str, Any]:
        store = _record_store()
        snapshot = store.get_record(remote_record_id)
        if snapshot is None:
            raise HTTPException(status_code=404, detail="record not found")
        record = snapshot.get("record", {})
        owner = record.get("operatorUserId")
        if owner and owner != user["id"]:
            raise HTTPException(status_code=404, detail="record not found")
        return _ok(snapshot)

    @app.post("/api/v1/records/{remote_record_id}/manual-review")
    def update_manual_review_v1(
        remote_record_id: str,
        payload: dict[str, Any] = Body(...),
        user: dict[str, Any] = Depends(_current_user),
    ) -> dict[str, Any]:
        store = _record_store()
        snapshot = store.update_manual_review(
            remote_record_id,
            payload,
            reviewer_user_id=user["id"],
        )
        if snapshot is None:
            raise HTTPException(status_code=404, detail="record not found")
        return _ok(
            {
                "remoteRecordId": snapshot["remoteRecordId"],
                "syncedAt": snapshot["syncedAt"],
            },
        )

    @app.post("/api/v1/diagnostics/mask-compare")
    async def compare_mask_v1(
        image: UploadFile = File(...),
        app_mask: str | None = Form(None, alias="appMask"),
        app_mask_file: UploadFile | None = File(None, alias="appMaskFile"),
        include_server_mask: bool = Form(True, alias="includeServerMask"),
        threshold: float = Form(0.3),
        max_windows: int = Form(20, alias="maxWindows"),
        user: dict[str, Any] = Depends(_current_user),
    ) -> dict[str, Any]:
        try:
            if app_mask_file is not None:
                app_mask_text = (await app_mask_file.read()).decode("utf-8")
            else:
                app_mask_text = app_mask
            if not app_mask_text:
                raise ValueError("appMask or appMaskFile is required")
            app_mask_value = parse_mask_json(app_mask_text)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        raw = await image.read()
        inference = _infer(raw, threshold=threshold, max_windows=max_windows)
        server_mask = inference.get("binaryMask")
        if not isinstance(server_mask, list):
            raise HTTPException(
                status_code=502, detail="server inference did not return a mask"
            )
        comparison = compare_masks(app_mask_value, server_mask)
        response = {
            **comparison,
            "server": {
                "crackRatio": inference.get("crackRatio"),
                "detectionCount": inference.get("detectionCount"),
                "modelVersion": inference.get("modelVersion"),
                "inferenceBackend": inference.get("inferenceBackend"),
            },
            "operatorUserId": user["id"],
        }
        if include_server_mask:
            response["server"]["binaryMask"] = server_mask
        return _ok(response)

    return app


def _ok(data: dict[str, Any], request_id: str | None = None) -> dict[str, Any]:
    return {
        "requestId": request_id or f"req_{uuid4().hex[:12]}",
        "success": True,
        "errorCode": "",
        "message": "ok",
        "data": data,
    }


def _error(
    status_code: int,
    error_code: str,
    message: str,
    *,
    detail: str | None = None,
) -> JSONResponse:
    body: dict[str, Any] = {
        "requestId": f"req_{uuid4().hex[:12]}",
        "success": False,
        "errorCode": error_code,
        "message": message,
        "data": {},
    }
    if detail:
        body["detail"] = detail
    return JSONResponse(status_code=status_code, content=body)


def _session(username: str) -> dict[str, Any]:
    return _session_for_user(
        {
            "id": "u_001",
            "username": username,
            "displayName": "施工人员",
            "role": "operator",
        }
    )


def _session_for_user(user: dict[str, Any]) -> dict[str, Any]:
    expires_at = datetime.now(UTC) + timedelta(hours=8)
    return {
        "accessToken": f"dev-access-{uuid4().hex}",
        "refreshToken": f"dev-refresh-{uuid4().hex}",
        "expiresAt": expires_at.isoformat().replace("+00:00", "Z"),
        "user": user,
    }


def _infer(
    raw: bytes,
    *,
    threshold: float,
    max_windows: int,
) -> dict[str, Any]:
    try:
        return run_inference(
            raw,
            threshold=threshold,
            max_windows=max_windows,
            server_version=SERVER_VERSION,
            model_version=MODEL_VERSION,
        )
    except InferenceError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


def _data_dir() -> Path:
    data_dir = Path(os.environ.get("CRACK_SERVER_DATA_DIR", "server/data"))
    data_dir.mkdir(parents=True, exist_ok=True)
    return data_dir


def _record_store() -> Any:
    if os.environ.get("CRACK_RECORD_STORE", "json").lower() == "mysql":
        return MySqlRecordStore()
    return RecordStore(_data_dir())


def _upsert_user_snapshot(user: dict[str, Any]) -> None:
    if os.environ.get("CRACK_RECORD_STORE", "json").lower() != "mysql":
        return
    MySqlRecordStore().upsert_user(user)


def _auth_disabled() -> bool:
    return os.environ.get("CRACK_AUTH_DISABLED", "true").lower() in {
        "1",
        "true",
        "yes",
    }


def _legacy_auth_enabled() -> bool:
    if _auth_disabled():
        return True
    return os.environ.get("CRACK_ENABLE_LEGACY_AUTH", "false").lower() in {
        "1",
        "true",
        "yes",
    }


def _mobile_oidc_config() -> dict[str, Any]:
    issuer = os.environ.get("CRACK_OIDC_ISSUER", "").rstrip("/")
    client_id = os.environ.get(
        "CRACK_OIDC_MOBILE_CLIENT_ID",
        os.environ.get("CRACK_MOBILE_CLIENT_ID", "crack-app-mobile"),
    )
    redirect_url = os.environ.get(
        "CRACK_OIDC_MOBILE_REDIRECT_URL",
        os.environ.get(
            "CRACK_MOBILE_REDIRECT_URL",
            "com.jinchuan.crackapp:/oauth2redirect",
        ),
    )
    scopes = [
        scope
        for scope in os.environ.get(
            "CRACK_OIDC_SCOPES",
            "openid profile email offline_access",
        ).split()
        if scope
    ]
    registration_url = os.environ.get("CRACK_OIDC_REGISTRATION_URL", "")
    if not registration_url and issuer:
        registration_url = (
            f"{issuer}/protocol/openid-connect/registrations?"
            + urlencode(
                {
                    "client_id": client_id,
                    "response_type": "code",
                    "scope": " ".join(scopes),
                    "redirect_uri": redirect_url,
                },
            )
        )
    return {
        "issuer": issuer,
        "clientId": client_id,
        "redirectUrl": redirect_url,
        "scopes": scopes,
        "registrationUrl": registration_url,
        "authEnabled": not _auth_disabled(),
    }


def _current_user(
    authorization: str | None = Header(default=None, alias="Authorization"),
    x_dev_user: str | None = Header(default=None, alias="X-Dev-User"),
) -> dict[str, Any]:
    if _auth_disabled():
        claims = _decode_dev_claims(x_dev_user)
        return _user_from_claims(claims)
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    claims = OidcTokenVerifier().verify(token)
    return _user_from_claims(claims)


def _decode_dev_claims(header_value: str | None) -> dict[str, Any]:
    if not header_value:
        return {
            "sub": "dev-user",
            "preferred_username": "dev",
            "name": "Developer",
            "realm_access": {"roles": ["operator"]},
        }
    try:
        decoded = json.loads(header_value)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="invalid X-Dev-User") from exc
    if not isinstance(decoded, dict):
        raise HTTPException(status_code=400, detail="invalid X-Dev-User")
    return decoded


def _user_from_claims(claims: dict[str, Any]) -> dict[str, Any]:
    realm_access = claims.get("realm_access") or {}
    roles = {str(role) for role in realm_access.get("roles") or []}
    role = next(
        (app_role for app_role in APP_ROLE_PRIORITY if app_role in roles),
        "operator",
    )
    username = str(
        claims.get("preferred_username")
        or claims.get("email")
        or claims.get("sub")
        or "unknown-user",
    )
    subject = str(claims.get("sub") or username)
    return {
        "id": subject,
        "username": username,
        "displayName": str(claims.get("name") or username),
        "role": role,
    }


class OidcTokenVerifier:
    def __init__(self) -> None:
        self.issuer = os.environ.get("CRACK_OIDC_ISSUER", "").rstrip("/")
        self.audience = os.environ.get("CRACK_OIDC_AUDIENCE", "")
        self.jwks_url = os.environ.get(
            "CRACK_OIDC_JWKS_URL",
            f"{self.issuer}/protocol/openid-connect/certs" if self.issuer else "",
        )

    def verify(self, token: str) -> dict[str, Any]:
        try:
            import jwt
            from jwt import PyJWKClient
        except ImportError as exc:
            raise HTTPException(
                status_code=503,
                detail="PyJWT is required for OIDC validation",
            ) from exc
        if not self.issuer or not self.audience or not self.jwks_url:
            raise HTTPException(status_code=503, detail="OIDC is not configured")
        try:
            key = PyJWKClient(self.jwks_url).get_signing_key_from_jwt(token).key
            claims = jwt.decode(
                token,
                key,
                algorithms=["RS256", "RS384", "RS512", "ES256"],
                audience=self.audience,
                issuer=self.issuer,
            )
        except Exception as exc:  # noqa: BLE001 - return stable API error
            raise HTTPException(status_code=401, detail="invalid bearer token") from exc
        if not isinstance(claims, dict):
            raise HTTPException(status_code=401, detail="invalid bearer token")
        return claims


class KeycloakNativeAuthClient:
    def __init__(self) -> None:
        self.issuer = os.environ.get("CRACK_OIDC_ISSUER", "").rstrip("/")
        self.client_id = os.environ.get(
            "CRACK_OIDC_MOBILE_CLIENT_ID",
            os.environ.get("CRACK_MOBILE_CLIENT_ID", "crack-app-mobile"),
        )
        self.scopes = os.environ.get(
            "CRACK_OIDC_SCOPES",
            "openid profile email offline_access",
        )
        self.realm = os.environ.get("CRACK_KEYCLOAK_REALM", "") or _realm_from_issuer(
            self.issuer
        )
        self.base_url = os.environ.get(
            "CRACK_KEYCLOAK_BASE_URL", ""
        ) or _keycloak_base_url(self.issuer)
        self.token_url = os.environ.get(
            "CRACK_KEYCLOAK_TOKEN_URL",
            f"{self.issuer}/protocol/openid-connect/token",
        )

    def login(self, username: str, password: str) -> dict[str, Any]:
        response = self._post_token(
            {
                "grant_type": "password",
                "client_id": self.client_id,
                "username": username,
                "password": password,
                "scope": self.scopes,
            }
        )
        return self._session_from_token_response(response)

    def refresh(self, refresh_token: str) -> dict[str, Any]:
        response = self._post_token(
            {
                "grant_type": "refresh_token",
                "client_id": self.client_id,
                "refresh_token": refresh_token,
            }
        )
        return self._session_from_token_response(response)

    def register(
        self,
        username: str,
        password: str,
        display_name: str,
        email: str = "",
    ) -> dict[str, Any]:
        admin_token = self._admin_token()
        user_id = self._create_user(
            admin_token,
            username=username,
            display_name=display_name,
            email=email,
        )
        self._set_password(admin_token, user_id, password)
        self._assign_operator_role(admin_token, user_id)
        return self.login(username, password)

    def guest(self, guest_id: str, display_name: str) -> dict[str, Any]:
        password = uuid4().hex + uuid4().hex
        admin_token = self._admin_token()
        try:
            user_id = self._create_user(
                admin_token,
                username=guest_id,
                display_name=display_name,
                email="",
            )
        except HTTPException as exc:
            if exc.status_code != 409:
                raise
            user_id = self._find_user_id(admin_token, guest_id)
        self._set_password(admin_token, user_id, password)
        self._assign_operator_role(admin_token, user_id)
        return self.login(guest_id, password)

    def _post_token(self, data: dict[str, str]) -> dict[str, Any]:
        try:
            with httpx.Client(timeout=20) as client:
                response = client.post(self.token_url, data=data)
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=502, detail="identity service unavailable"
            ) from exc
        if response.status_code >= 400:
            raise HTTPException(status_code=401, detail="invalid credentials")
        body = response.json()
        if not isinstance(body, dict):
            raise HTTPException(status_code=502, detail="invalid token response")
        return body

    def _admin_token(self) -> str:
        username = os.environ.get("CRACK_KEYCLOAK_ADMIN_USERNAME") or os.environ.get(
            "KEYCLOAK_ADMIN", ""
        )
        password = os.environ.get("CRACK_KEYCLOAK_ADMIN_PASSWORD") or os.environ.get(
            "KEYCLOAK_ADMIN_PASSWORD", ""
        )
        admin_realm = os.environ.get("CRACK_KEYCLOAK_ADMIN_REALM", "master")
        admin_client_id = os.environ.get("CRACK_KEYCLOAK_ADMIN_CLIENT_ID", "admin-cli")
        if not self.base_url or not username or not password:
            raise HTTPException(
                status_code=503, detail="registration is not configured"
            )
        token_url = (
            f"{self.base_url}/realms/{admin_realm}/protocol/openid-connect/token"
        )
        try:
            with httpx.Client(timeout=20) as client:
                response = client.post(
                    token_url,
                    data={
                        "grant_type": "password",
                        "client_id": admin_client_id,
                        "username": username,
                        "password": password,
                    },
                )
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=502, detail="identity service unavailable"
            ) from exc
        if response.status_code >= 400:
            raise HTTPException(
                status_code=503, detail="registration is not configured"
            )
        token = response.json().get("access_token")
        if not token:
            raise HTTPException(
                status_code=502, detail="admin token response missing access token"
            )
        return str(token)

    def _create_user(
        self,
        admin_token: str,
        *,
        username: str,
        display_name: str,
        email: str,
    ) -> str:
        if not self.base_url or not self.realm:
            raise HTTPException(
                status_code=503, detail="registration is not configured"
            )
        resolved_display_name = display_name or username
        payload: dict[str, Any] = {
            "username": username,
            "enabled": True,
            "email": _registration_email(username, email),
            "emailVerified": True,
            "firstName": resolved_display_name,
            "lastName": username,
        }
        url = f"{self.base_url}/admin/realms/{self.realm}/users"
        headers = {"Authorization": f"Bearer {admin_token}"}
        try:
            with httpx.Client(timeout=20) as client:
                response = client.post(url, headers=headers, json=payload)
                if response.status_code == 409:
                    raise HTTPException(
                        status_code=409, detail="username already exists"
                    )
                if response.status_code not in {201, 204}:
                    raise HTTPException(
                        status_code=502, detail="failed to create account"
                    )
                location = response.headers.get("Location", "")
                user_id = location.rstrip("/").split("/")[-1] if location else ""
                if user_id:
                    return user_id
                lookup = client.get(
                    url,
                    headers=headers,
                    params={"username": username, "exact": "true"},
                )
        except HTTPException:
            raise
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=502, detail="identity service unavailable"
            ) from exc
        if lookup.status_code >= 400:
            raise HTTPException(
                status_code=502, detail="failed to find created account"
            )
        users = lookup.json()
        if not isinstance(users, list) or not users:
            raise HTTPException(
                status_code=502, detail="failed to find created account"
            )
        return str(users[0]["id"])

    def _find_user_id(self, admin_token: str, username: str) -> str:
        if not self.base_url or not self.realm:
            raise HTTPException(
                status_code=503, detail="registration is not configured"
            )
        url = f"{self.base_url}/admin/realms/{self.realm}/users"
        headers = {"Authorization": f"Bearer {admin_token}"}
        try:
            with httpx.Client(timeout=20) as client:
                response = client.get(
                    url,
                    headers=headers,
                    params={"username": username, "exact": "true"},
                )
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=502, detail="identity service unavailable"
            ) from exc
        if response.status_code >= 400:
            raise HTTPException(status_code=502, detail="failed to find guest account")
        users = response.json()
        if not isinstance(users, list) or not users:
            raise HTTPException(status_code=502, detail="failed to find guest account")
        return str(users[0]["id"])

    def _set_password(self, admin_token: str, user_id: str, password: str) -> None:
        if not self.base_url or not self.realm:
            raise HTTPException(
                status_code=503, detail="registration is not configured"
            )
        url = (
            f"{self.base_url}/admin/realms/{self.realm}/users/{user_id}/reset-password"
        )
        headers = {"Authorization": f"Bearer {admin_token}"}
        payload = {
            "type": "password",
            "value": password,
            "temporary": False,
        }
        try:
            with httpx.Client(timeout=20) as client:
                response = client.put(url, headers=headers, json=payload)
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=502, detail="identity service unavailable"
            ) from exc
        if response.status_code >= 400:
            raise HTTPException(
                status_code=502, detail="failed to set account password"
            )

    def _assign_operator_role(self, admin_token: str, user_id: str) -> None:
        if not self.base_url or not self.realm:
            return
        headers = {"Authorization": f"Bearer {admin_token}"}
        role_url = f"{self.base_url}/admin/realms/{self.realm}/roles/operator"
        mapping_url = (
            f"{self.base_url}/admin/realms/{self.realm}/users/{user_id}"
            "/role-mappings/realm"
        )
        try:
            with httpx.Client(timeout=20) as client:
                role_response = client.get(role_url, headers=headers)
                if role_response.status_code >= 400:
                    return
                client.post(mapping_url, headers=headers, json=[role_response.json()])
        except httpx.HTTPError:
            return

    def _session_from_token_response(self, body: dict[str, Any]) -> dict[str, Any]:
        access_token = str(body.get("access_token") or "")
        refresh_token = str(body.get("refresh_token") or "")
        if not access_token:
            raise HTTPException(
                status_code=502, detail="token response missing access token"
            )
        claims = _decode_jwt_without_verification(access_token)
        user = _user_from_claims(claims)
        exp = claims.get("exp")
        if isinstance(exp, (int, float)):
            expires_at = datetime.fromtimestamp(exp, tz=UTC)
        else:
            expires_in = int(body.get("expires_in") or 3600)
            expires_at = datetime.now(UTC) + timedelta(seconds=expires_in)
        return {
            "accessToken": access_token,
            "refreshToken": refresh_token,
            "expiresAt": expires_at.isoformat().replace("+00:00", "Z"),
            "user": user,
        }


def _realm_from_issuer(issuer: str) -> str:
    marker = "/realms/"
    if marker not in issuer:
        return ""
    return issuer.rsplit(marker, maxsplit=1)[-1].strip("/")


def _keycloak_base_url(issuer: str) -> str:
    marker = "/realms/"
    if marker not in issuer:
        return ""
    return issuer.split(marker, maxsplit=1)[0].rstrip("/")


def _decode_jwt_without_verification(token: str) -> dict[str, Any]:
    parts = token.split(".")
    if len(parts) < 2:
        return {}
    try:
        payload = parts[1] + "=" * (-len(parts[1]) % 4)
        decoded = base64.urlsafe_b64decode(payload.encode("ascii"))
        value = json.loads(decoded.decode("utf-8"))
    except (ValueError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _registration_email(username: str, email: str) -> str:
    if email:
        return email
    local_part = re.sub(r"[^A-Za-z0-9_.+-]+", ".", username).strip(".").lower()
    if not local_part:
        local_part = uuid4().hex
    domain = os.environ.get("CRACK_DEFAULT_EMAIL_DOMAIN", "users.example.invalid")
    return f"{local_part}@{domain}"


def _guest_id(value: str) -> str:
    candidate = _safe_segment(value)
    if re.fullmatch(r"guest_\d{8}_[A-Za-z0-9]{4,12}", candidate):
        return candidate
    date_part = datetime.now(UTC).strftime("%Y%m%d")
    return f"guest_{date_part}_{uuid4().hex[:4]}"


def _guest_display_name(guest_id: str) -> str:
    suffix = guest_id.rsplit("_", maxsplit=1)[-1]
    return f"访客 {suffix}"


def _asset_timestamp(value: Any) -> str:
    if value is None:
        return datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    text = str(value).strip()
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=UTC)
        return parsed.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ")
    except ValueError:
        return _safe_segment(text)


class ObjectStoragePresigner:
    def __init__(self) -> None:
        self.bucket = os.environ.get("CRACK_OBJECT_BUCKET", "crack-record-assets")
        self.public_endpoint = os.environ.get(
            "CRACK_OBJECT_PUBLIC_ENDPOINT",
            "http://localhost:9000",
        ).rstrip("/")

    def presign_uploads(
        self,
        *,
        record_id: str,
        assets: list[Any],
        user: dict[str, Any],
        metadata: dict[str, Any],
    ) -> list[dict[str, Any]]:
        uploads: list[dict[str, Any]] = []
        base_name = self._upload_base_name(
            record_id=record_id,
            user=user,
            metadata=metadata,
        )
        safe_record_id = _safe_segment(record_id)
        folder = f"{base_name}/{safe_record_id}"
        for asset in assets:
            if not isinstance(asset, dict):
                continue
            kind = _safe_segment(str(asset.get("kind") or "asset"))
            file_name = _safe_file_name(str(asset.get("fileName") or f"{kind}.bin"))
            unique_name = (
                f"{base_name}_{safe_record_id}_{kind}_{uuid4().hex}_{file_name}"
            )
            object_key = f"records/{folder}/{kind}/{unique_name}"
            content_type = str(asset.get("contentType") or "application/octet-stream")
            uploads.append(
                {
                    "kind": kind,
                    "bucket": self.bucket,
                    "objectKey": object_key,
                    "uploadUrl": self._presigned_put_url(object_key, content_type),
                    "downloadUrl": self._download_url(object_key),
                    "headers": {"Content-Type": content_type},
                    "ownerUserId": user["id"],
                    "sha256": asset.get("sha256"),
                    "sizeBytes": asset.get("sizeBytes"),
                },
            )
        return uploads

    def _upload_base_name(
        self,
        *,
        record_id: str,
        user: dict[str, Any],
        metadata: dict[str, Any],
    ) -> str:
        engineering = metadata.get("engineeringInfo")
        if not isinstance(engineering, dict):
            engineering = {}
        timestamp = _asset_timestamp(metadata.get("timestamp"))
        username = str(user.get("username") or "").strip()
        parts = [
            _safe_value_segment(user.get("id"), "unknown"),
            _safe_value_segment(
                _storage_display_name(user.get("displayName"), username),
                "unknown",
            ),
            _safe_value_segment(
                engineering.get("workerName") or engineering.get("inspector"),
                "未填报告人",
            ),
            _safe_value_segment(engineering.get("projectName"), "未填项目"),
            _safe_value_segment(
                engineering.get("projectLocation") or engineering.get("location"),
                "未填地点",
            ),
            _safe_segment(timestamp),
        ]
        return "_".join(parts)

    def _presigned_put_url(self, object_key: str, content_type: str) -> str:
        client = self._s3_client()
        if client is None:
            return f"{self._download_url(object_key)}?dev-presigned-put=1"
        return str(
            client.generate_presigned_url(
                "put_object",
                Params={
                    "Bucket": self.bucket,
                    "Key": object_key,
                    "ContentType": content_type,
                },
                ExpiresIn=900,
            ),
        )

    def _download_url(self, object_key: str) -> str:
        return self.download_url(object_key)

    def download_url(self, object_key: str) -> str:
        client = self._s3_client()
        if client is not None:
            return str(
                client.generate_presigned_url(
                    "get_object",
                    Params={"Bucket": self.bucket, "Key": object_key},
                    ExpiresIn=900,
                ),
            )
        return f"{self.public_endpoint}/{self.bucket}/{object_key}"

    def _s3_client(self) -> Any | None:
        try:
            import boto3
        except ImportError:
            return None
        endpoint_url = os.environ.get("CRACK_S3_ENDPOINT_URL")
        access_key = os.environ.get("CRACK_S3_ACCESS_KEY_ID")
        secret_key = os.environ.get("CRACK_S3_SECRET_ACCESS_KEY")
        if not endpoint_url or not access_key or not secret_key:
            return None
        return boto3.client(
            "s3",
            endpoint_url=endpoint_url,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
        )


def _safe_segment(value: str) -> str:
    return re.sub(r"[^\w.-]+", "_", value, flags=re.UNICODE).strip("._") or "item"


def _safe_value_segment(value: Any, fallback: str) -> str:
    text = str(value or "").strip()
    if not text:
        text = fallback
    return _safe_segment(text)


def _storage_display_name(display_name: Any, username: str) -> str:
    text = str(display_name or username or "").strip()
    username = username.strip()
    if username and text.endswith(username):
        text = text[: -len(username)].strip()
    return text or username


def _safe_file_name(value: str) -> str:
    return _safe_segment(Path(value).name)


class RecordStore:
    def __init__(self, data_dir: Path) -> None:
        self.data_dir = data_dir
        self.records_path = data_dir / "records.json"
        self.keys_path = data_dir / "idempotency_keys.json"

    def sync_record(
        self,
        record: dict[str, Any],
        idempotency_key: str,
    ) -> dict[str, Any]:
        records = self._read_json(self.records_path)
        keys = self._read_json(self.keys_path)
        existing_remote_id = keys.get(idempotency_key)
        if existing_remote_id and existing_remote_id in records:
            return records[existing_remote_id]

        record_id = str(record.get("id") or record.get("recordId") or uuid4().hex)
        remote_record_id = str(record.get("remoteRecordId") or f"cloud_{record_id}")
        synced_at = datetime.now(UTC).isoformat().replace("+00:00", "Z")
        normalized_record = {
            **record,
            "id": record_id,
            "remoteRecordId": remote_record_id,
            "syncStatus": "uploaded",
            "syncError": "",
            "updatedAt": record.get("updatedAt") or synced_at,
        }
        snapshot = {
            "remoteRecordId": remote_record_id,
            "syncedAt": synced_at,
            "record": normalized_record,
        }
        records[remote_record_id] = snapshot
        keys[idempotency_key] = remote_record_id
        self._write_json(self.records_path, records)
        self._write_json(self.keys_path, keys)
        return snapshot

    def list_records(self, owner_id: str | None = None) -> list[dict[str, Any]]:
        records = self._read_json(self.records_path)
        values = list(records.values())
        if owner_id:
            values = [
                item
                for item in values
                if not item.get("record", {}).get("operatorUserId")
                or item.get("record", {}).get("operatorUserId") == owner_id
            ]
        return sorted(
            values,
            key=lambda item: str(item.get("syncedAt", "")),
            reverse=True,
        )

    def list_reports(
        self,
        *,
        owner_id: str | None = None,
        presigner: ObjectStoragePresigner,
    ) -> list[dict[str, Any]]:
        reports: list[dict[str, Any]] = []
        for snapshot in self.list_records(owner_id=owner_id):
            record = snapshot.get("record", {})
            if not isinstance(record, dict):
                continue
            owner = str(record.get("operatorUserId") or owner_id or "dev-user")
            engineering = record.get("engineeringInfo") or {}
            for asset in record.get("assets") or []:
                if not isinstance(asset, dict) or asset.get("kind") != "report":
                    continue
                object_key = str(asset.get("objectKey") or "")
                if not object_key:
                    continue
                username = "dev" if owner == "dev-user" else owner
                display_name = "Developer" if owner == "dev-user" else username
                reports.append(
                    {
                        "userId": owner,
                        "username": username,
                        "displayName": display_name,
                        "remoteRecordId": snapshot.get("remoteRecordId"),
                        "timestamp": record.get("timestamp", ""),
                        "projectName": engineering.get("projectName") or "",
                        "downloadUrl": presigner.download_url(object_key),
                    }
                )
        return reports

    def get_record(self, remote_record_id: str) -> dict[str, Any] | None:
        records = self._read_json(self.records_path)
        record = records.get(remote_record_id)
        if isinstance(record, dict):
            return record
        return None

    def update_manual_review(
        self,
        remote_record_id: str,
        manual_review: dict[str, Any],
        *,
        reviewer_user_id: str,
    ) -> dict[str, Any] | None:
        records = self._read_json(self.records_path)
        snapshot = records.get(remote_record_id)
        if not isinstance(snapshot, dict):
            return None
        record = snapshot.get("record")
        if not isinstance(record, dict):
            return None
        record["manualReview"] = {
            **manual_review,
            "reviewerUserId": reviewer_user_id,
        }
        synced_at = datetime.now(UTC).isoformat().replace("+00:00", "Z")
        record["updatedAt"] = synced_at
        snapshot["syncedAt"] = synced_at
        self._write_json(self.records_path, records)
        return snapshot

    def _read_json(self, path: Path) -> dict[str, Any]:
        if not path.exists():
            return {}
        try:
            content = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return {}
        if isinstance(content, dict):
            return content
        return {}

    def _write_json(self, path: Path, data: dict[str, Any]) -> None:
        path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True),
            encoding="utf-8",
        )


app = create_app()
