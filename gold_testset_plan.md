# Gold Testset Plan: crack_app
> Generated: 2026-06-08  
> Tier: A-core  
> Project bucket: Mobile app + FastAPI showcase / engineering delivery  
> Priority score: 87  
> GitHub: https://github.com/DavidZhu258/crack_app

## Evaluation Goal

验证 Flutter app + FastAPI server 能作为可交付系统稳定完成支护决策展示。

## Target Gold Set

- Target size: **60**
- Eval type: `mobile_api_workflow`
- Seed cases created now: **3**
- First next step from matrix: 加一份 acceptance_tests.md + 10 个 API/UI smoke cases。

## Test-set Design

40-80 个业务流程案例：上传、推理/模拟推理、结果展示、错误处理、无网络、缺模型权重。

## Metrics

Accuracy metrics:

```text
workflow pass rate; API response correctness; UI state correctness; decision-output consistency; error message correctness
```

Feasibility metrics:

```text
fresh build; Android install; server start; p95 API latency; offline/weak-network behavior; proprietary-weight fallback
```

Rubric seed metrics:

- workflow_pass_rate
- api_correctness
- ui_state_correctness
- safe_error_rate
- fresh_setup_success
- p95_latency

## Required Hard Cases

无模型权重、图片过大、网络中断、接口返回异常、移动端权限缺失。

## Build Plan

1. Replace the 3 placeholder seed cases in `evals/gold/seed_gold.jsonl` with real examples.
2. Fill `evals/gold/annotation_template.csv` with expected labels, evidence references, and reviewer status.
3. Run a manual seed evaluation and save raw output in `evals/results/`.
4. Only after the seed suite is stable, expand `evals/gold/full_gold.jsonl` toward the target size.
5. Publish evidence only when the report includes both accuracy and feasibility metrics.

## Acceptance Bar

For portfolio use, the project must pass all seed hard negatives, have a reproducible fresh-run path, and show at least one saved result artifact under `evals/results/`.

## Evidence to Add

APK/demo video、API docs、验收清单、无权重可演示路径。
