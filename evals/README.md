# evals/ for crack_app

Minimum evaluation scaffold for `crack_app`.

## Layout

```text
evals/
  gold/seed_gold.jsonl
  gold/full_gold.jsonl
  gold/annotation_template.csv
  rubrics/rubric.yaml
  scripts/README.md
  fixtures/
  results/
```

## Contract

- Eval type: `mobile_api_workflow`
- Target full gold size: `60`
- Seed cases: `3`
- Metrics: workflow_pass_rate, api_correctness, ui_state_correctness, safe_error_rate, fresh_setup_success, p95_latency

Replace placeholders with real fixtures/records before using any result as portfolio evidence.
