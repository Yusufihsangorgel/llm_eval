import 'check_result.dart';
import 'eval_case.dart';
import 'eval_report.dart';
import 'model_call.dart';
import 'response_cache.dart';

/// A collection of [EvalCase]s that run together against one model.
class EvalSuite {
  /// Creates a suite over [cases].
  EvalSuite(this.cases);

  /// The cases the suite runs, in report order.
  final List<EvalCase> cases;

  /// Runs every case against [model] and returns an [EvalReport].
  ///
  /// At most [concurrency] cases run at the same time. Results keep the
  /// order of [cases] regardless of completion order.
  ///
  /// When [cache] is given, each attempt first looks the prompt up in the
  /// cache and only calls [model] on a miss; the response is then written
  /// back. The cache key combines [modelId] and the prompt, so responses
  /// from different models do not collide. [modelId] is also recorded in
  /// the report.
  ///
  /// When [repeat] is greater than 1, each case runs that many times
  /// (sequentially within the case) and the report exposes a flakiness
  /// rate. Run flakiness measurements without a cache: after the first
  /// attempt warms the cache, later attempts return the same response.
  ///
  /// A model call that throws marks that attempt with a model error and
  /// does not affect other cases. A check that throws is recorded as an
  /// error result on that check.
  ///
  /// [concurrency] and [repeat] must be at least 1.
  Future<EvalReport> run(
    ModelCall model, {
    int concurrency = 4,
    ResponseCache? cache,
    int repeat = 1,
    String? modelId,
  }) async {
    if (concurrency < 1) {
      throw ArgumentError.value(concurrency, 'concurrency', 'must be >= 1');
    }
    if (repeat < 1) {
      throw ArgumentError.value(repeat, 'repeat', 'must be >= 1');
    }
    final results = List<CaseResult?>.filled(cases.length, null);
    var nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < cases.length) {
        final index = nextIndex++;
        results[index] = await _runCase(
          cases[index],
          model,
          cache: cache,
          repeat: repeat,
          modelId: modelId,
        );
      }
    }

    final workerCount = concurrency < cases.length ? concurrency : cases.length;
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
    return EvalReport(
      results: [for (final r in results) r!],
      repeat: repeat,
      modelId: modelId,
    );
  }

  Future<CaseResult> _runCase(
    EvalCase evalCase,
    ModelCall model, {
    required ResponseCache? cache,
    required int repeat,
    required String? modelId,
  }) async {
    final attempts = <AttemptResult>[];
    for (var i = 0; i < repeat; i++) {
      attempts.add(
        await _runAttempt(evalCase, model, cache: cache, modelId: modelId),
      );
    }
    return CaseResult(caseId: evalCase.id, attempts: attempts);
  }

  Future<AttemptResult> _runAttempt(
    EvalCase evalCase,
    ModelCall model, {
    required ResponseCache? cache,
    required String? modelId,
  }) async {
    final stopwatch = Stopwatch()..start();
    final key = '${modelId ?? ''}\n${evalCase.prompt}';
    String? output;
    var fromCache = false;
    if (cache != null) {
      output = await cache.read(key);
      fromCache = output != null;
    }
    if (output == null) {
      try {
        output = await model(evalCase.prompt);
      } catch (e) {
        stopwatch.stop();
        return AttemptResult(
          output: '',
          checks: const [],
          latency: stopwatch.elapsed,
          fromCache: false,
          modelError: e.toString(),
        );
      }
      if (cache != null) await cache.write(key, output);
    }
    stopwatch.stop();
    final outcomes = <CheckOutcome>[];
    for (final check in evalCase.checks) {
      CheckResult result;
      try {
        result = await check.evaluate(output);
      } catch (e) {
        result = CheckResult.error('check threw: $e');
      }
      outcomes.add(
        CheckOutcome(description: check.description, result: result),
      );
    }
    return AttemptResult(
      output: output,
      checks: outcomes,
      latency: stopwatch.elapsed,
      fromCache: fromCache,
    );
  }
}
