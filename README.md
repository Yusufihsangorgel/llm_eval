# llm_eval

![llm_eval banner](https://raw.githubusercontent.com/Yusufihsangorgel/llm_eval/main/doc/banner.png)

A test harness for LLM outputs in Dart. Write eval cases the way you write
unit tests: a prompt, a list of checks, and a report you can read in CI.

`llm_eval` does not talk to any model provider. You hand it one function
that takes a prompt and returns the model output, and it handles running
cases concurrently, checking outputs, caching responses, and reporting.

## Why

Dart and Flutter apps that call LLMs usually have no automated way to catch
a prompt regression. Model output is not exact, so plain string equality in
a unit test does not work. This package covers the middle ground. It gives
you assertion-style checks for the properties that must hold. For the fuzzy
parts, there is an optional LLM judge. A response cache keeps CI runs
deterministic and free.

## Quick start

```dart
import 'package:llm_eval/llm_eval.dart';

Future<void> main() async {
  // Bind your model. Any Future<String> Function(String prompt) works:
  // an OpenAI or Anthropic SDK call, an Ollama HTTP request, a fake.
  Future<String> model(String prompt) async {
    // ... call your model client here ...
    return 'The capital of France is Paris.';
  }

  final suite = EvalSuite([
    EvalCase(
      id: 'capital-question',
      prompt: 'What is the capital of France?',
      checks: [
        Check.contains('paris'),
        Check.notContains('berlin'),
      ],
    ),
    EvalCase(
      id: 'structured-output',
      prompt: 'Return a JSON object with a "city" field.',
      checks: [
        Check.isValidJson(where: (v) => v is Map && v.containsKey('city')),
      ],
    ),
  ]);

  final report = await suite.run(model, modelId: 'my-model');
  print(report.toMarkdown());
}
```

Run the bundled example with `dart run example/llm_eval_example.dart`.

## Checks

| Check | Passes when |
| --- | --- |
| `Check.contains(s)` | the output contains `s` (case-insensitive by default) |
| `Check.notContains(s)` | the output does not contain `s` |
| `Check.matches(regExp)` | the pattern matches the output |
| `Check.isValidJson(where: f)` | the output parses as JSON and the optional condition holds |
| `Check.predicate(desc, f)` | your function returns true |
| `Check.judge(...)` | another model scores the output at or above `passAt` |

Custom checks implement the `Check` interface: a `description` for reports
and an `evaluate` method that returns a `CheckResult`.

Fails and errors are distinct throughout. A fail means the check ran and
the output did not satisfy it. An error means no verdict was possible (the
judge response could not be parsed, a callback threw, the model call
failed). Reports show them separately, so a broken harness is not mistaken
for a failing model.

## LLM as judge

For properties that plain checks cannot express, ask another model to grade
the output against a rubric:

```dart
Check.judge(
  judge: judgeModel, // often a stronger model than the one under test
  rubric: 'The answer names Paris and stays under three sentences.',
  passAt: 0.7,
)
```

The judge receives the rubric and the output in a fixed prompt and must
answer with a `SCORE: <number>` line between 0.0 and 1.0. A response that
cannot be parsed becomes an error result, never a silent pass or fail. So
does a response with conflicting score lines, which is what a graded
output that smuggles in its own `SCORE: 1.0` line tends to produce. The
graded output is wrapped in delimiters the judge is told to respect; this
raises the bar against prompt injection without eliminating it.

One honest caveat: the judge is itself an LLM. Its scores are not
calibrated, they drift across judge models and versions, and they can be
wrong. Use judges sparingly, pin the judge model, and spot-check its
verdicts against your own reading.

## Caching and CI

The core library is pure Dart and runs on every platform, including the
web. `FileResponseCache` needs `dart:io`, so it lives in a separate
library:

```dart
import 'package:llm_eval/llm_eval.dart';
import 'package:llm_eval/io.dart' show FileResponseCache;

final cache = FileResponseCache('test/llm_cache');
final report = await suite.run(model, cache: cache, modelId: 'my-model-v1');
```

The first run calls the model and stores each response in a file named
after the SHA-256 of the model id and prompt. Later runs read the cache and
never call the model. Commit the cache directory and your CI eval job is
deterministic, offline, and free. Delete the directory, or change
`modelId`, to re-record.

A regression test then looks like any other test:

```dart
test('prompt regression suite', () async {
  final report = await suite.run(
    model,
    cache: FileResponseCache('test/llm_cache'),
    modelId: 'my-model-v1',
  );
  expect(report.results, isNotEmpty);
  expect(report.errorCount, 0, reason: report.toMarkdown());
  expect(report.passRate, 1.0, reason: report.toMarkdown());
});
```

The same shape works as a standalone CI gate:

```dart
final report = await suite.run(model, cache: cache, modelId: 'my-model-v1');
stdout.writeln(report.toMarkdown());
if (report.results.isEmpty || report.errorCount > 0 || report.passRate < 1.0) {
  exitCode = 1;
}
```

Check `errorCount` separately from the pass rate: errors mean the harness
could not produce a verdict (a judge response failed to parse, a callback
threw), not that the model answered badly. Note that an empty suite has a
pass rate of 1.0, so guard against accidentally building zero cases, as
both snippets above do.

## Repeat and flakiness

```dart
final report = await suite.run(model, repeat: 5);
print(report.flakinessRate);
```

Each case runs five times and the report exposes the fraction of cases
whose attempts disagree. Measure flakiness without a cache: a warm cache
returns the same response every time.

## Reports

`EvalReport.toMarkdown()` renders a summary table plus details for every
non-passing case, suitable for a CI job summary. `EvalReport.toJson()`
returns a JSON-compatible map with the full result tree (outputs, per-check
verdicts, scores, latencies, cache hits) for your own tooling.

## Planned

Out of scope for 0.1 and planned for later releases:

- side-by-side comparison of several models over one suite
- token and cost accounting
- dataset loaders for existing eval formats
- structured prompts: system messages and multi-turn conversations

## License

MIT
