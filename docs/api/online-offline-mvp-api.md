# 线上/离线 MVP API 契约

## 通用响应

所有接口返回统一结构：

```json
{
  "requestId": "req_20260504_0001",
  "success": true,
  "errorCode": "",
  "message": "ok",
  "data": {}
}
```

错误时 `success=false`，`errorCode` 使用稳定枚举，例如 `UNAUTHORIZED`、`VALIDATION_ERROR`、`SERVER_BUSY`、`MODEL_ERROR`。

## GET /health

用途：客户端判断服务器真实可达性。  
成功响应：

```json
{
  "requestId": "req_health",
  "success": true,
  "errorCode": "",
  "message": "ok",
  "data": {
    "serverVersion": "mvp-1.0.0",
    "modelVersion": "savss_256",
    "status": "ready"
  }
}
```

## Enterprise v1 Auth

生产环境的手机端登录/注册使用 App 内用户名密码表单提交到本服务的
`/api/v1/auth/*` 接口；服务端再与 Keycloak 通信并返回 App 会话。Keycloak
仍然是身份源，API 请求仍携带 Bearer token。

- API 请求携带 `Authorization: Bearer <access-token>`。
- 服务端按环境变量 `CRACK_OIDC_ISSUER`、`CRACK_OIDC_AUDIENCE`、
  `CRACK_OIDC_JWKS_URL` 校验 issuer、audience、签名和过期时间。
- 本地测试可设置 `CRACK_AUTH_DISABLED=true`，并用 `X-Dev-User` 注入开发
  claims；生产不得启用。
- App 登录成功后必须调用 `/api/v1/me`。只有服务端接受 Bearer token 并
  返回用户快照时，App 才把登录视为成功，并把服务端确认的用户信息写回安全
  token 存储。
- `/api/v1/auth/config` 仍返回 OIDC/Keycloak 配置，供 App 判断服务端登录
  服务是否启用；移动端 UI 不再启动浏览器授权码流程。

### GET /api/v1/auth/config

用途：App 只需要输入服务器地址，即可从后端读取登录服务状态和移动端
Keycloak 配置。该接口不要求 Bearer token。移动端当前只用它显示服务状态，
不再打开 `registrationUrl`。

响应 `data`：

```json
{
  "issuer": "https://id.example.com/realms/crack",
  "clientId": "crack-app-mobile",
  "redirectUrl": "com.jinchuan.crackapp:/oauth2redirect",
  "scopes": ["openid", "profile", "email", "offline_access"],
  "registrationUrl": "https://id.example.com/realms/crack/protocol/openid-connect/registrations?...",
  "authEnabled": true
}
```

### POST /api/v1/auth/login

用途：App 内账号密码登录。服务端使用 Keycloak direct password grant 换取
token，并返回 App 已有的 `AuthSession` 结构。

请求：

```json
{
  "username": "miner01",
  "password": "password"
}
```

成功响应 `data`：

```json
{
  "accessToken": "access-token",
  "refreshToken": "refresh-token",
  "expiresAt": "2026-05-13T12:00:00Z",
  "user": {
    "id": "oidc-sub",
    "username": "miner01",
    "displayName": "施工人员",
    "role": "operator"
  }
}
```

### POST /api/v1/auth/register

用途：App 内注册并登录。App 只需要提交用户名、密码，以及可选姓名/邮箱；
服务端负责创建 Keycloak 用户、补齐当前 realm 要求的资料字段、设置密码、
分配 `operator` 角色并返回登录会话。

请求：

```json
{
  "username": "newminer",
  "password": "secret123",
  "displayName": "新矿工",
  "email": "optional@example.com"
}
```

成功响应 `data` 与 `/api/v1/auth/login` 相同。

### POST /api/v1/auth/refresh

用途：App 使用安全存储中的 refresh token 换取新会话。

请求：

```json
{
  "refreshToken": "refresh-token"
}
```

成功响应 `data` 与 `/api/v1/auth/login` 相同。

### GET /api/v1/me

返回当前 OIDC 用户映射：

```json
{
  "id": "oidc-sub",
  "username": "miner01",
  "displayName": "张三",
  "role": "operator"
}
```

### POST /api/v1/uploads/presign

用途：为原图、结果图、mask、报告等大对象申请 S3/MinIO 预签名上传地址。
MySQL 只保存返回的 bucket/objectKey/metadata，不保存图片 BLOB。

请求：

```json
{
  "recordId": "jci_001",
  "assets": [
    {
      "kind": "originalImage",
      "fileName": "face.jpg",
      "contentType": "image/jpeg",
      "sha256": "hex",
      "sizeBytes": 123456
    }
  ]
}
```

响应 `data`：

```json
{
  "uploads": [
    {
      "kind": "originalImage",
      "bucket": "crack-record-assets",
      "objectKey": "records/jci_001/originalImage/uuid_face.jpg",
      "uploadUrl": "https://minio.example/presigned-put",
      "downloadUrl": "https://minio.example/crack-record-assets/records/...",
      "headers": {
        "Content-Type": "image/jpeg"
      }
    }
  ]
}
```

### POST /api/v1/records/sync

企业版记录同步接口，语义与旧 `/records/sync` 相同，但要求 Bearer token。
请求体允许额外包含：

```json
{
  "assets": [
    {
      "kind": "originalImage",
      "bucket": "crack-record-assets",
      "objectKey": "records/jci_001/originalImage/uuid_face.jpg",
      "sha256": "hex",
      "contentType": "image/jpeg",
      "sizeBytes": 123456,
      "width": 1024,
      "height": 768
    }
  ],
  "formulaSnapshot": {
    "scores": {
      "R1": 2,
      "R2": 8,
      "R3": 8,
      "RMR": "22.000000",
      "Q": "0.008800",
      "gQ": "29.444827",
      "hS": "-0.257690",
      "JCI": "20.314887"
    }
  }
}
```

### POST /api/v1/records/{remoteRecordId}/manual-review

用途：单独更新人工复核结果。

```json
{
  "acceptedRecognitionResult": false,
  "manualGrade": "IV",
  "selectedSupportPlan": {},
  "reviewerName": "王工",
  "note": "现场破碎带更发育",
  "reviewedAt": "2026-05-07T09:30:00Z"
}
```

### Formula Parity

App 与 Server 共享 `test/fixtures/jci_formula_cases.json`。离散分值
`R1/R2/R3` 必须完全一致；浮点项统一输出 6 位小数字符串后比较 JSON。
该验证只证明同一输入下公式一致，不证明手机 ONNX 与服务器模型 mask 完全
一致。

## POST /auth/login

用途：旧版开发接口。生产 `CRACK_AUTH_DISABLED=false` 时默认返回 404；移动端
应使用 `/api/v1/auth/login`。离线检测不依赖登录。

请求：

```json
{
  "username": "miner01",
  "password": "password"
}
```

成功响应 `data`：

```json
{
  "accessToken": "access-token",
  "refreshToken": "refresh-token",
  "expiresAt": "2026-05-04T12:00:00Z",
  "user": {
    "id": "u_001",
    "username": "miner01",
    "displayName": "施工人员",
    "role": "operator"
  }
}
```

## POST /auth/refresh

用途：旧版开发接口。生产 `CRACK_AUTH_DISABLED=false` 时默认返回 404；移动端
应使用 `/api/v1/auth/refresh`。

请求：

```json
{
  "refreshToken": "refresh-token"
}
```

响应与 `/auth/login` 相同。

## POST /inference/crack

用途：服务器端 ONNX Runtime 裂隙分割推理。请求使用 `multipart/form-data`。

字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `image` | file | 掌子面图片 |
| `threshold` | number | 二值化阈值，默认 0.3 |
| `maxWindows` | number | 滑窗上限，默认 20 |

成功响应 `data`：

```json
{
  "crackRatio": 6.12,
  "inferenceTime": 1200,
  "detectionCount": 1,
  "resultImage": "base64-jpg",
  "binaryMask": [[false, true], [false, false]],
  "originalWidth": 1024,
  "originalHeight": 512,
  "modelVersion": "savss_256",
  "serverVersion": "mvp-1.0.0"
}
```

## POST /records/sync

用途：上传本地检测记录。客户端使用 `Idempotency-Key` 请求头，格式为 `recordId_updatedAt`。
服务端必须按该请求头做幂等处理：同一 key 重复上传时返回同一个 `remoteRecordId`。

请求：

```json
{
  "id": "jci_001",
  "timestamp": "2026-05-04T12:30:00Z",
  "operatorUserId": "u_001",
  "inferenceMode": "offline",
  "modelVersion": "savss_256",
  "engineeringInfo": {},
  "indicators": {
    "indicator1": 2.0,
    "indicator2": 20.0,
    "indicator3": 0.65
  },
  "jciResult": {},
  "classification": {},
  "supportPlan": {},
  "manualReview": {
    "acceptedRecognitionResult": false,
    "manualGrade": "IV",
    "selectedSupportPlan": {},
    "reviewerName": "王工",
    "note": "现场破碎带更发育",
    "reviewedAt": "2026-05-07T09:30:00Z"
  },
  "images": {
    "image1Path": "local-path-or-upload-token",
    "image2Path": "local-path-or-upload-token"
  }
}
```

成功响应 `data`：

```json
{
  "remoteRecordId": "cloud_jci_001",
  "syncedAt": "2026-05-04T12:31:00Z"
}
```

## GET /records

用途：下载云端已保存检测记录，用于 App 联网后恢复或比对记录。

成功响应 `data`：

```json
{
  "records": [
    {
      "remoteRecordId": "cloud_jci_001",
      "syncedAt": "2026-05-04T12:31:00Z",
      "record": {
        "id": "jci_001",
        "remoteRecordId": "cloud_jci_001",
        "syncStatus": "uploaded",
        "manualReview": {}
      }
    }
  ]
}
```

## GET /records/{remoteRecordId}

用途：按云端记录 ID 下载单条检测记录。  
成功响应 `data` 为单条记录快照：

```json
{
  "remoteRecordId": "cloud_jci_001",
  "syncedAt": "2026-05-04T12:31:00Z",
  "record": {}
}
```

## 客户端处理规则

- `GET /health` 超时或失败时，自动模式走手机端离线推理。
- `POST /inference/crack` 失败时，自动模式回退离线；`onlineOnly` 模式抛出错误。
- `POST /records/sync` 失败时只更新本地同步状态，不删除本地记录。
- `GET /records` 成功时，客户端将云端记录保存到本地并标记为 `uploaded`。
- 人工复核字段 `manualReview` 必须随记录一起上传和下载。
- 登录 token 仅保存到安全存储，不写入检测 JSON。
