# Evaluation Results
> Last updated: 2026-06-09

This repository now includes a lightweight, GitHub-visible seed-gold evaluation scaffold.

## What is tested now

- `evals/gold/seed_gold.jsonl` contains 3 real repository-grounded seed cases.
- Every seed case references files that exist in this repository.
- At least one seed case is a hard-negative/safety/refusal case.
- `evals/scripts/validate_seed.py` writes `evals/results/latest_seed_validation.json`.
- GitHub Actions workflow `.github/workflows/eval-seed-validation.yml` runs the same validator on pushes and pull requests touching `evals/**`.

## Current limitation

This seed validation proves traceability and feasibility scaffolding. It does **not** yet prove final model/product accuracy. Full quality claims require expanding `evals/gold/full_gold.jsonl` and adding project-specific model/system runners.

## Local command

```bash
python evals/scripts/validate_seed.py
```

## Result artifact

See `evals/results/latest_seed_validation.json` after running the validator locally or in GitHub Actions.

## GitHub CI status note

`Eval Seed Validation` passes for this PR and writes `evals/results/latest_seed_validation.json`.

As of 2026-06-09, the repository's pre-existing `crack_app` workflow also runs on pull requests. Its failed checks are separate from the seed evaluation scaffold:

- `semantic-pull-request / build`: the PR title must use a Conventional Commit prefix. The PR title has been updated to `test: add seed gold evaluation validation`.
- `spell-check / build`: the existing full-repository Markdown spell check reports project/domain vocabulary such as `ONNX`, `savss`, `jinchuan`, `pytest`, and `evals`. This is a repository dictionary/configuration issue rather than a seed validator failure.
- `build / build`: the existing Very Good reusable Flutter workflow pins `flutter_version: "3.35.x"`, which provides Dart 3.9.2, while the reusable workflow installs `very_good_cli 1.1.1`, which currently requires Dart >=3.11.0. This is a CI toolchain drift issue outside the seed validator.

Therefore the evaluation evidence is GitHub-visible and passing, while full PR green status requires a separate CI maintenance change for the existing Flutter/spell-check workflow.
