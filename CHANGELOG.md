## 0.1.3

- Example: use the suite as a CI gate. It now exits non-zero when any case
  fails, the way you wire it into a build step, instead of only printing a
  report.

## 0.1.2

- Docs: sharpen the pub.dev description to lead with the value and the terms people search.

## 0.1.1

- Docs: tightened the README wording and visuals.

# Changelog

## 0.1.0

Initial release.

- `EvalCase`, `EvalSuite`, and `EvalReport` with Markdown and JSON output.
- Built-in checks: `contains`, `notContains`, `matches`, `isValidJson`,
  `predicate`, and LLM-as-judge scoring with `Check.judge`.
- `ResponseCache` interface in the core and a file-backed
  `FileResponseCache` in `package:llm_eval/io.dart` (atomic writes) for
  deterministic reruns in CI.
- Concurrent case execution with stable result order.
- Repeat runs with a flakiness rate.
