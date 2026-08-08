// A complete CI gate for an LLM feature, in one file.
//
// `llm_eval_example.dart` shows the shape of a suite. This one shows the job
// people actually need done: turn an eval suite into a build step that goes
// red on a prompt regression, tells a human what broke, tells the CI system
// which case broke, and costs nothing to rerun.
//
// Four things happen below, and each maps to something a real pipeline needs:
//
//   1. FileResponseCache      run it twice; the second run never calls the
//                             model, so CI is deterministic and free.
//   2. report.toMarkdown()    the human view, for a PR comment or job summary.
//   3. report.toJUnitXml()    the machine view, so the CI UI lists each case.
//   4. errorCount / passRate  two different reasons to fail, kept apart.
//
// The suite below is deliberately red. A green example would teach you
// nothing about the part you care about: what a failure looks like when it
// reaches your CI UI at 2am.
//
// Run it, then run it again:
//
//   dart run example/ci_gate.dart   # cold cache: 4 model calls
//   dart run example/ci_gate.dart   # warm cache: 1 model call
//
// Both runs exit 1. That is the point.

import 'dart:io';

import 'package:llm_eval/io.dart' show FileResponseCache;
import 'package:llm_eval/llm_eval.dart';

/// How many times the model was actually called during this run.
///
/// A real cache is invisible from the outside: the report looks the same
/// whether an answer came from the model or from disk. Counting the calls is
/// the only honest way to show that the second run is free.
var modelCalls = 0;

/// Stands in for your model client, so this example needs no key and no
/// network. In a real project this is one OpenAI, Anthropic, Gemini or
/// Ollama call; everything else on this page stays as it is.
///
/// The canned answers are what a *regressed* model returns. Imagine the
/// answers below arrived after a routine version bump: still fluent, still
/// plausible, and quietly wrong in two different ways.
Future<String> upgradedModel(String prompt) async {
  modelCalls++;

  if (prompt.contains('capital of France')) {
    // The regression. The fact is right, so a human skimming a diff of model
    // outputs would sign off on it. The hedge in front of it is what breaks
    // the product: this string is rendered into a UI that promised short,
    // confident answers.
    return 'As an AI language model I cannot be certain, but the capital '
        'of France is generally considered to be Paris.';
  }

  if (prompt.contains('JSON')) {
    // Chat-tuned models wrap JSON in a markdown fence even when you ask them
    // not to. `Check.isValidJson` strips a single wrapping fence before it
    // gives up, so this passes -- your parser is the thing that has to cope,
    // and this check tells you whether it still can.
    return '```json\n'
        '{"city": "Paris", "country": "France"}\n'
        '```';
  }

  if (prompt.contains('rate limit demo')) {
    // Providers return 429 under load. This is not a prompt regression and
    // must not be reported as one -- see the gate at the bottom.
    throw const HttpException('429 Too Many Requests: quota exceeded');
  }

  return 'Paris is the capital of France.';
}

Future<void> main() async {
  final suite = EvalSuite([
    EvalCase(
      id: 'capital-question',
      prompt: 'What is the capital of France? Answer in one sentence.',
      checks: [
        // Two checks on one output. The first still passes: the answer is
        // correct. The second is the one that catches the regression, which
        // is why "did the model get it right?" is the wrong question to
        // build a gate on.
        Check.contains('paris'),
        Check.notContains('as an ai'),
      ],
    ),
    EvalCase(
      id: 'structured-output',
      prompt: 'Return JSON with "city" and "country" keys. JSON only.',
      checks: [
        Check.isValidJson(
          where: (decoded) => decoded is Map && decoded['city'] == 'Paris',
        ),
      ],
    ),
    EvalCase(
      id: 'answer-stays-short',
      prompt: 'Name the capital of France.',
      checks: [
        // Length is a cost and latency budget, not a style preference: this
        // string is going into a push notification.
        Check.predicate(
          'at most 120 characters',
          (output) => output.length <= 120,
        ),
      ],
    ),
    EvalCase(
      id: 'rate-limit-demo',
      prompt: 'Anything at all (rate limit demo).',
      checks: [Check.contains('paris')],
    ),
  ]);

  // Committing this directory is what makes the eval job free and offline.
  // This example keeps its cache under example/.eval_cache and .gitignore
  // excludes it, so the two-run demo starts cold for every reader. A real
  // project commits it -- this repository commits its own eval cache under
  // tool/eval_cache for exactly that reason.
  final cacheDir = Platform.script.resolve('.eval_cache').toFilePath();
  final cache = FileResponseCache(cacheDir);

  final report = await suite.run(
    upgradedModel,
    cache: cache,
    // The model id is part of the cache key. Bump it when you switch models
    // and every answer re-records; leave it alone and you keep replaying the
    // answers you already reviewed.
    modelId: 'demo-model-v2',
  );

  // 1. The human view.
  stdout.writeln(report.toMarkdown());

  // 2. The machine view. Point your CI at this file and the run stops being
  //    a wall of log output: each case becomes a row, and a failing row
  //    expands to the checks that failed and the output that failed them.
  final xmlPath = Platform.script.resolve('eval-results.xml').toFilePath();
  File(xmlPath).writeAsStringSync(report.toJUnitXml());

  // 3. The cache, made visible.
  final cached = report.results.where((r) => r.attempts.first.fromCache).length;
  stdout.writeln(
    '\nmodel calls this run: $modelCalls   '
    'answers served from cache: $cached/${report.results.length}',
  );
  if (modelCalls > 0 && cached > 0) {
    // A call that throws is never written to the cache, so the rate-limited
    // case retries on every run while the others stay offline. That is the
    // behaviour you want: a cache should not freeze an outage into a fixture.
    stdout.writeln(
      'the remaining call is rate-limit-demo: failed calls are not cached',
    );
  }

  // 4. The gate. Two failure modes, deliberately not merged into one number.
  //
  //    passRate  answers to "did the model do its job?"  -- a product problem.
  //    errorCount answers to "did we get an answer at all?" -- an
  //               infrastructure problem. A 429, a judge whose reply could
  //               not be parsed, a callback that threw.
  //
  //    Folding them together produces the worst possible incident: a
  //    provider outage that reads on the dashboard as "the new prompt is
  //    bad", and an afternoon spent editing a prompt that was fine.
  //
  //    The empty-suite guard is not paranoia. An empty report has a pass rate
  //    of 1.0, so a glob that stops matching your case files turns the gate
  //    green instead of red.
  final reasons = <String>[
    if (report.results.isEmpty) 'the suite is empty (nothing ran)',
    if (report.errorCount > 0)
      'harness/infrastructure errors: ${report.errorCount}',
    if (report.passRate < 1.0)
      'cases that did not pass: '
          '${report.results.length - report.passedCount}',
  ];

  stdout.writeln('\nJUnit XML written to $xmlPath');
  if (reasons.isEmpty) {
    stdout.writeln('gate: PASS');
    exitCode = 0;
    return;
  }
  stdout.writeln('gate: FAIL');
  for (final reason in reasons) {
    stdout.writeln('  - $reason');
  }
  exitCode = 1;
}
