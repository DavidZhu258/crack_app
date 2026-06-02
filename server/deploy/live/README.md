# Live Enterprise Stack

This folder is for the remote WSL smoke environment under
`/home/crack/app/cloud_dev`. It starts only infrastructure services:
Keycloak, MySQL, and MinIO. FastAPI still runs from the separate
`crack_cloud` conda environment.

Do not commit a real `.env`. Copy `.env.example` to `.env` on the remote
machine and replace every value there.

Ports are bound to `127.0.0.1` inside WSL by default:

- Keycloak: `8080`
- MySQL: `3306`
- MinIO S3: `9000`
- MinIO console: `9001`

FastAPI live settings should point at:

- `CRACK_AUTH_DISABLED=false`
- `CRACK_OIDC_ISSUER=http://127.0.0.1:8080/realms/crack`
- `CRACK_OIDC_AUDIENCE=crack-app-api`
- `CRACK_OIDC_MOBILE_CLIENT_ID=crack-app-mobile`
- `CRACK_OIDC_MOBILE_REDIRECT_URL=com.jinchuan.crackapp:/oauth2redirect`
- `CRACK_OIDC_SCOPES=openid profile email offline_access`
- `CRACK_RECORD_STORE=mysql`
- `CRACK_MYSQL_DSN=mysql+pymysql://<CRACK_DB_USERNAME>:<CRACK_DB_PASSWORD>@127.0.0.1:3306/<CRACK_DB_NAME>?charset=utf8mb4`
- `CRACK_S3_ENDPOINT_URL=http://127.0.0.1:9000`
- `CRACK_OBJECT_PUBLIC_ENDPOINT=http://127.0.0.1:9000`
- `CRACK_OBJECT_BUCKET=crack-record-assets`

Mobile App login flow:

1. Enter the FastAPI base URL in the App login dialog.
2. Tap `读取服务器登录配置`; the App calls `/api/v1/auth/config` and fills the
   OIDC issuer/client/redirect values.
3. Tap `注册账号` only when a new Keycloak account is needed. Registration is
   handled by Keycloak; the App never stores passwords.
4. Tap login. After AppAuth returns a token, the App calls `/api/v1/me`. The
   login is treated as successful only if the API accepts the Bearer token and
   returns the server-confirmed user snapshot.

Smoke flow:

1. Start Docker services with `docker compose up -d`.
2. Apply `server/db/mysql_schema.sql` to the `crack_app` database.
3. Start FastAPI from `crack_cloud` with the live environment variables.
4. Run `python server/scripts/live_smoke.py` with the test user's password in
   the process environment.
