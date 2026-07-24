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
