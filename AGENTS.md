# llm_eval

`llm_eval` runs `EvalCase`s (a prompt plus `Check`s) against a `ModelCall` the
caller supplies, then produces an `EvalReport`. It does not call any provider,
does not ship prompts, and does not judge without a `ModelCall` you pass to
`Check.judge`.

## Usage

You write the `ModelCall` (`Future<String> Function(String prompt)`). The
harness does not. Shape taken from `example/llm_eval_example.dart`:

```dart
import 'package:llm_eval/llm_eval.dart';

Future<String> fakeModel(String prompt) async {
  if (prompt.contains('capital of France')) {
    return 'The capital of France is Paris.';
  }
  return 'I do not know.';
}

Future<void> main() async {
  final suite = EvalSuite([
    EvalCase(
      id: 'capital-question',
      prompt: 'What is the capital of France?',
      checks: [Check.contains('paris'), Check.notContains('berlin')],
    ),
  ]);
  final report = await suite.run(fakeModel, modelId: 'fake-model');
  print(report.toMarkdown());
}
```

Replace `fakeModel` with your client. For a file cache, also
`import 'package:llm_eval/io.dart' show FileResponseCache`.

## Contracts

**Cache key (`EvalSuite.run`, `ResponseCache.wrap`).** The key is
`'${label.length}:$label\n$prompt'` where `label` is `modelId` or `''`.
`FileResponseCache` stores SHA-256 of that UTF-8 string as `<digest>.txt`.
The key is only `modelId` and the prompt — not the case id, not the checks,
not the body of the `ModelCall`. Change the client, a system prompt, or
sampling and leave `modelId` alone: `AttemptResult.fromCache` is true and
the old answer is reused. A thrown `ModelCall` is never written. `repeat > 1`
with a cache throws `ArgumentError`. `Check.judge` is not covered by
`EvalSuite.run`'s cache; wrap it.

**Baseline (`EvalBaseline`, `diffAgainstBaseline`).**
`EvalBaseline.fromReport` records per-case `id`, `passed`, `flaky`, and the
lowest check score keyed by `Check.description`. Commit `toJsonString()`;
reload with `EvalBaseline.parse`. The diff matches on case id, not
`EvalReport.passRate`. `EvalDiff.hasRegressions` is true for `regressions`
(pass→fail), `scoreDrops` past `scoreTolerance` (default `0.05`),
`becameFlaky`, and `removedCases`. Fixes and `newCases` do not set it. A model-id change is
reported (`EvalDiff.modelChanged`), not refused.

**Judge (`Check.judge`).** Needs a `ModelCall` that replies with a
`SCORE: <n>` line, `n` in `[0.0, 1.0]`. Pass when `score >= passAt` (default
`0.7`). Missing, conflicting, or out-of-range scores, or a throw, become
`CheckResult.error` — never a silent pass or fail. Cache it with
`cache.wrap(judge, modelId: 'judge-v1')` and a distinct `modelId`.
`AttemptResult.fromCache` is only the model under test.

**Concurrency (`EvalSuite.run`).** Default `concurrency` is 4. Up to four
cases call `ModelCall` at once; in-flight identical prompts are not
deduplicated. A rate-limited client sees that burst. A throw (for example a
429) is `AttemptResult.modelError` (error, not fail) and is not cached, so
it retries every run. Lower `concurrency` if the client cannot take four.

## Mistakes

- **Stale cache, green suite.** Same `modelId` and prompt after the
  `ModelCall` changed. Symptom: `fromCache: true`, the new client is never
  called. Fix: bump `modelId` or delete the cache directory.
- **Pass rate hides a swap.** One case broke and another was fixed, or the
  failing case was deleted. Symptom: `passRate` unchanged or up, product
  worse. Fix: `diffAgainstBaseline` and fail on `hasRegressions`
  (`example/baseline_diff.dart`).
- **Unwrapped judge.** Warm cache, `fromCache` true, judge still called.
  Fix: `ResponseCache.wrap` with its own `modelId`.
- **Empty suite.** `EvalReport.passRate` is `1.0` when `results` is empty.
  Fix: require `report.results.isNotEmpty` (`example/ci_gate.dart`).
- **`FileResponseCache` is not in `package:llm_eval/llm_eval.dart`.** Import
  `package:llm_eval/io.dart`.
- **Errors vs fails.** A thrown model call or unparsable judge is
  `errorCount`, not a prompt regression. Gate `errorCount == 0` separately
  from `passRate`.
- **`repeat` plus a cache.** Throws. Measure flakiness without a cache.
- **`Check.contains` is case-insensitive** unless `caseSensitive: true`.

## Layout

- `lib/llm_eval.dart` — public API. `lib/io.dart` — `FileResponseCache`.
  `lib/src/` — implementation.
- `example/` — all fakes, no provider.
- `test/` — unit tests. `tool/eval.dart` and committed `tool/eval_cache/` —
  replay-only gate.

```
dart test
dart run example/llm_eval_example.dart
dart run example/judge.dart
dart run example/baseline_diff.dart
dart run example/mcp_tool_eval.dart
```

`dart run example/ci_gate.dart` exits 1 by design.
