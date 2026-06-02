# Open Source Release Checklist

This checklist records the public-release boundary for this project.

## Do Not Commit

Do not publish:

- `assets/models/savss_256.onnx`
- `lib/crack/*.ptl`
- `artifacts/` and all APK/model conversion outputs
- `build/`, `.dart_tool/`, `.gradle_noproxy/`, `.pytest_cache/`
- `android/key.properties`, `android/app/upload-keystore.jks`, any keystore or
  signing key
- `.env` files, Cloudflare tunnel tokens, SSH keys, Keycloak/MinIO/MySQL
  passwords
- `codex/`, `codex-project-summary.md`, local exports, local checkpoints
- generated `.backup_*` document/image backups and local `.docx` manuals

## Safe Public Materials

These are intended to be safe for the public repository:

- Flutter and FastAPI source code
- API contract documentation
- model placement instructions
- sample images under `assets/images/test/`
- showcase screenshots under `docs/showcase/`
- current app icon and generated launcher resources
- `.env.example` files containing placeholders only
- Markdown documentation such as README, API docs, and this checklist

## Before Pushing

Run these checks from the project root:

```powershell
git status --ignored
git check-ignore assets\models\savss_256.onnx lib\crack\savss_mobile_224.ptl android\key.properties android\app\upload-keystore.jks
rg -n --hidden --glob '!build/**' --glob '!artifacts/**' --glob '!codex/**' "BEGIN .*PRIVATE KEY|AKIA[0-9A-Z]{16}|password=|secret=" .
flutter analyze
flutter test
python -m pytest server\tests -q
python -m compileall -q server\app server\scripts
```

Also manually confirm that no tunnel tokens, SSH keys, or real service
credentials are staged.

If the workspace is not yet a Git repository, run `git init` only after this
checklist is satisfied, then use `git add .` and inspect staged files before
committing.

## Model Policy

The open-source repository does not include our pretrained model. External
users can either:

- place their own compatible ONNX model at `assets/models/savss_256.onnx`, or
- configure the app to use their own server inference endpoint through
  `CRACK_API_BASE_URL`.

Do not use Git LFS to publish the private model unless a separate legal and
licensing decision explicitly approves it.
