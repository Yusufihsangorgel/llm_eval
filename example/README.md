# llm_eval example

`llm_eval_example.dart` runs a small eval suite against a fake, deterministic
model — no key, no network — so you can see the whole shape: cases, checks per
case, and the Markdown report it prints. Swap the fake `ModelCall` for a real
one and nothing else changes.

```dart
final suite = EvalSuite([
  EvalCase(
    id: 'capital-question',
    prompt: 'What is the capital of France?',
    checks: [Check.contains('paris'), Check.notContains('berlin')],
  ),
  EvalCase(
    id: 'structured-output',
    prompt: 'Reply with JSON: {"city": "..."}',
    checks: [Check.isValidJson(/* ... */)],
  ),
  // ...more cases
]);

final report = await suite.run(fakeModel, modelId: 'fake-model');
print(report.toMarkdown());
```

Run it:

```
dart run example/llm_eval_example.dart
```

Output:

```
# llm_eval report

- model: `fake-model`
- cases: 3
- pass rate: 100.0% (3/3)

| case | status | checks | latency | cached |
| --- | --- | --- | --- | --- |
| capital-question | pass | 2/2 | 6ms | no |
| structured-output | pass | 1/1 | 3ms | no |
| unknown-question | pass | 1/1 | 10ms | no |

3/3 cases passed
```

The report is also available as JSON, and a `FileResponseCache` (in
`package:llm_eval/io.dart`) lets a suite reuse a model's answers across runs so
an eval that only changed its checks does not pay for the model again.

## `ci_gate.dart` — the same suite as a build step

`llm_eval_example.dart` shows the shape of a suite. `ci_gate.dart` shows the
job people actually need done: turn a suite into a CI step that goes red on a
prompt regression, tells a human what broke, tells the CI system which case
broke, and costs nothing to rerun.

```
dart run example/ci_gate.dart   # cold cache: 4 model calls
dart run example/ci_gate.dart   # warm cache: 1 model call
```

Both runs exit 1, and that is the point — a green example teaches you nothing
about the part you care about, which is what a failure looks like when it
reaches your CI UI at 2am. The suite is deliberately regressed:

```
| case               | status | checks | latency | cached |
| ------------------ | ------ | ------ | ------- | ------ |
| capital-question   | fail   | 1/2    | 6ms     | no     |
| structured-output  | pass   | 1/1    | 2ms     | no     |
| answer-stays-short | pass   | 1/1    | 2ms     | no     |
| rate-limit-demo    | error  | -      | 2ms     | no     |

gate: FAIL
  - harness/infrastructure errors: 1
  - cases that did not pass: 2
```

Four things in that output are worth more than the API surface:

1. **`capital-question` fails with 1/2 checks passing.** The answer names
   Paris; it also opens with "As an AI language model I cannot be certain".
   The fact is right and the answer is unusable, which is why "did the model
   get it right?" is the wrong question to build a gate on.
2. **`rate-limit-demo` is an `error`, not a `fail`.** A 429 means no verdict
   was possible. Fold errors into the pass rate and a provider outage reads on
   the dashboard as "the new prompt is bad" — then someone spends an afternoon
   editing a prompt that was fine.
3. **The second run makes one model call instead of four.** Three answers come
   off disk. The one that still calls is `rate-limit-demo`: a call that threw
   is never written to the cache, so an outage is not frozen into a fixture.
4. **`eval-results.xml` is written next to the example.** Point a CI reporter
   at it and each case becomes a row, with the failing one expanded to the
   check that failed and the output that failed it.

The cache lands in `example/.eval_cache/` and is intentionally not committed,
so every reader starts cold and sees both runs. A real project commits it —
this repository commits its own under `tool/eval_cache/`, which is what lets
[`tool/eval.dart`](../tool/eval.dart) run as a CI step with no model, no key
and no network.
