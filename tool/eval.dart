// The eval gate this package tells you to build, running against this package.
//
// The README claims an eval suite can be a CI step that is deterministic,
// offline and free. This file is that claim, executed: `dart run
// tool/eval.dart` is a step in this repository's own CI, and on the GitHub
// runner there is no Ollama, no API key and no network path to a model. Every
// response is replayed from `tool/eval_cache/`, which is committed.
//
// Two rules make that work, and they are the interesting part:
//
//   1. The cache is committed. That is the whole trick. A response recorded
//      once is a fixture like any other, and a fixture costs nothing to
//      replay.
//   2. Replay is the default; calling a model needs `--record`. An eval gate
//      that quietly reaches for a model on a cache miss is a bug: it makes CI
//      nondeterministic, chargeable, and dependent on a provider's uptime. A
//      miss should go red and say so.
//
// Usage:
//
//   dart run tool/eval.dart              # replay only; what CI runs
//   dart run tool/eval.dart --record     # allow calls to a local Ollama
//
// To re-record after changing a prompt or the model: delete the entry (or the
// whole directory) and run with --record, with Ollama serving _modelId.

import 'dart:convert';
import 'dart:io';

import 'package:llm_eval/io.dart' show FileResponseCache;
import 'package:llm_eval/llm_eval.dart';

/// The model under test, pinned.
///
/// The label is part of the cache key, so this string is load-bearing:
/// changing it invalidates every recorded response on purpose. That is how you
/// force a re-record when you switch models, and why you should never write
/// something vague like "local" here.
const _modelId = 'qwen2.5:0.5b';

/// The judge model, pinned separately.
///
/// Same model as the one under test, which is a compromise worth naming: the
/// README recommends a judge stronger than the model being graded. This
/// repository uses a 0.5B model for both because the point of this file is
/// that CI replays a recording from disk, and a recorded judge response is a
/// fixture whose provenance matters more than its size.
///
/// Giving the judge its own id keeps its responses distinct from the model's
/// in the same directory, so re-recording one does not disturb the other.
const _judgeId = 'qwen2.5:0.5b-judge';

const _ollamaHost = 'localhost';
const _ollamaPort = 11434;

/// Model calls actually made this run. Zero is the expected value in CI.
var _modelCalls = 0;

/// Calls a local Ollama server.
///
/// `temperature: 0` is not a style preference. Recording a fixture from a
/// sampling model means recording one draw from a distribution; at
/// temperature 0 a re-record after an unrelated prompt edit produces the same
/// text instead of a diff full of noise.
Future<String> _callOllama(String model, String prompt) async {
  _modelCalls++;
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.http('$_ollamaHost:$_ollamaPort', '/api/generate'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'model': model,
        'prompt': prompt,
        'stream': false,
        'options': {'temperature': 0},
      }),
    );
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != 200) {
      throw HttpException('Ollama returned ${response.statusCode}: $body');
    }
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return decoded['response'] as String;
  } finally {
    client.close(force: true);
  }
}

/// Wraps [model] so it only reaches the network when [recording] is true.
///
/// The suite consults the cache first, so this runs on a miss and nowhere
/// else. In CI [recording] is false and a miss throws, which the harness turns
/// into a model error rather than an assertion failure -- exactly the
/// distinction the gate at the bottom relies on. A missing fixture is a broken
/// harness, not a bad model.
ModelCall _replayOnly(String model, {required bool recording}) {
  return (String prompt) async {
    if (!recording) {
      throw StateError(
        'no cached response for this prompt under "$model", and this run is '
        'replay-only. Start Ollama with the $_modelId model and rerun with '
        '--record to record it.',
      );
    }
    return _callOllama(model, prompt);
  };
}

/// The suite: what this repository expects from a small local model.
///
/// Every case is a property that would be worth a bug report if it stopped
/// holding, not a demonstration of an API.
EvalSuite _buildSuite(ResponseCache cache, {required bool recording}) {
  return EvalSuite([
    EvalCase(
      id: 'names-the-capital',
      prompt: 'What is the capital of France? Answer in one short sentence.',
      checks: [
        Check.contains('paris'),
        // Hedging preambles are a real regression mode: the fact stays right
        // while the answer becomes unusable in a UI that promised a short,
        // confident sentence.
        Check.notContains('as an ai'),
      ],
    ),
    EvalCase(
      id: 'json-shape',
      prompt:
          'Return only a JSON object with the keys "city" and "country" for '
          'the capital of France. No prose.',
      checks: [
        // Worth reading the recorded fixture for this one. The prompt says
        // "no prose" and the model wraps the object in a ```json fence
        // anyway. `Check.isValidJson` strips a single wrapping fence before
        // giving up, so this passes -- and the recorded response is evidence
        // that the fence-stripping path exists because real models behave
        // this way, not because it was convenient to implement.
        Check.isValidJson(
          where: (decoded) => decoded is Map && decoded['city'] == 'Paris',
        ),
      ],
    ),
    EvalCase(
      id: 'stays-short',
      prompt: 'In one sentence, what is a neutron star?',
      checks: [
        // A length budget, not a style rule: this string is rendered into a
        // two-line tooltip. 200 characters is what fits.
        Check.predicate(
          'at most 200 characters',
          (output) => output.trim().length <= 200,
        ),
      ],
    ),
    EvalCase(
      id: 'does-not-refuse',
      prompt: 'In one sentence, what causes a solar eclipse?',
      checks: [
        Check.judge(
          // Wrapping the judge is the part that is easy to miss. `suite.run`
          // caches the model under test; a judge runs *inside* a check and
          // never touches that cache. Leave it unwrapped and a warm cache
          // still fires the judge on every run -- the suite stops being
          // offline and stops being free, quietly. `cache.wrap` gives it the
          // same key scheme, so judge and model responses sit side by side in
          // one directory.
          judge: cache.wrap(
            _replayOnly(_modelId, recording: recording),
            modelId: _judgeId,
          ),
          // This rubric asks the judge for the one distinction it was
          // measured to be reliable at. See the calibration note below.
          rubric:
              'The output answers the question directly. It does not '
              'refuse, defer, or say it cannot help.',
          // The package default. Not tuned to make this suite green.
          passAt: 0.7,
        ),
      ],
    ),
  ]);
}

// Judge calibration, measured against this judge on 2026-08-08 before the
// rubric above was chosen. Six verdicts, temperature 0:
//
//   rubric "states that Paris is the capital"
//     "The capital of France is Paris."          1.00   correct
//     "The capital of France is Berlin."         0.75   WRONG -- passes at 0.7
//     "I am not able to answer questions ..."    0.00   correct
//   rubric "answers directly, does not refuse"
//     a direct one-sentence answer               0.75   correct
//     "I am sorry, but I cannot help ..."        0.00   correct
//     "You should consult an expert ..."         0.75   WRONG -- a deferral
//
// Two of six are wrong at the default threshold, and the expensive one is the
// first: a 0.5B judge scored a factually wrong answer 0.75. That is why
// correctness in this suite is gated by `Check.contains('paris')`, which costs
// nothing and cannot be talked out of it, and the judge is only asked whether
// the model refused -- a 0.00 vs 0.75 gap wide enough to survive an
// uncalibrated grader. Spot-check your own judge the same way before you trust
// a number it produced.

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln(
      'Usage: dart run tool/eval.dart [--record]\n'
      '\n'
      '  (no flags)  replay recorded responses only; never calls a model\n'
      '  --record    call a local Ollama server on a cache miss and store it\n',
    );
    return;
  }
  final recording = args.contains('--record');

  // Committed, unlike the cache in example/ci_gate.dart. This directory is the
  // reason CI needs no model.
  final cacheDir = Platform.script.resolve('eval_cache').toFilePath();
  final cache = FileResponseCache(cacheDir);
  final suite = _buildSuite(cache, recording: recording);

  final report = await suite.run(
    _replayOnly(_modelId, recording: recording),
    cache: cache,
    modelId: _modelId,
    // One at a time. A single local model serializes on one GPU anyway, so
    // concurrency here buys nothing and makes a recording run harder to read.
    concurrency: 1,
  );

  // The human view: printed, and appended to the CI job summary by the
  // workflow.
  final markdown = report.toMarkdown();
  stdout.writeln(markdown);
  final root = Platform.script.resolve('..');
  File(root.resolve('eval-report.md').toFilePath()).writeAsStringSync(markdown);

  // The machine view: each case becomes a row in the CI UI, and a failing row
  // expands to the checks that failed and the output that failed them.
  final xmlPath = root.resolve('eval-results.xml').toFilePath();
  File(xmlPath).writeAsStringSync(report.toJUnitXml());

  final replayed = report.results
      .where((r) => r.attempts.first.fromCache)
      .length;
  stdout.writeln(
    'model calls: $_modelCalls   '
    'replayed from cache: $replayed/${report.results.length}   '
    '(judge calls are inside the checks and not counted in the column above)',
  );
  stdout.writeln('report:  $xmlPath');

  // The gate. Errors and failures are kept apart on purpose: `errorCount`
  // means the harness could not produce a verdict (a missing fixture, a judge
  // reply that would not parse), `passRate` means the model answered badly.
  // Folding them into one number turns a missing cache entry into "the prompt
  // regressed", and someone spends an afternoon editing a prompt that was
  // fine.
  //
  // The empty-suite guard is not paranoia: an empty report has a pass rate of
  // 1.0, so a suite that silently builds zero cases would report success.
  final reasons = <String>[
    if (report.results.isEmpty) 'the suite is empty (nothing ran)',
    if (report.errorCount > 0)
      'harness errors: ${report.errorCount} (missing fixture, or a judge '
          'reply that could not be parsed)',
    if (report.passRate < 1.0)
      'cases that did not pass: '
          '${report.results.length - report.passedCount}',
  ];

  if (reasons.isEmpty) {
    stdout.writeln('gate: PASS');
    return;
  }
  stdout.writeln('gate: FAIL');
  for (final reason in reasons) {
    stdout.writeln('  - $reason');
  }
  exitCode = 1;
}
