# Changelog

## 0.1.0

Initial release.

- `EvalCase`, `EvalSuite`, and `EvalReport` with Markdown and JSON output.
- Built-in checks: `contains`, `notContains`, `matches`, `isValidJson`,
  `predicate`, and LLM-as-judge scoring with `Check.judge`.
- `ResponseCache` interface and `FileResponseCache` for deterministic
  reruns in CI.
- Concurrent case execution with stable result order.
- Repeat runs with a flakiness rate.
