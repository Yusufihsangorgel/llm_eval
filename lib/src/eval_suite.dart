import 'check_result.dart';
import 'error_detail.dart';
import 'eval_case.dart';
import 'eval_report.dart';
import 'model_call.dart';
import 'response_cache.dart';

/// A collection of [EvalCase]s that run together against one model.
final class EvalSuite {
  /// Creates a suite over [cases].
  ///
  /// [cases] is copied, so mutating the list you pass in afterwards does not
  /// change what the suite runs.
  EvalSuite(List<EvalCase> cases) : cases = List.unmodifiable(cases);

  /// The cases the suite runs, in report order.
  final List<EvalCase> cases;

  /// Runs every case against [model] and returns an [EvalReport].
  ///
  /// At most [concurrency] cases run at the same time. Results keep the
  /// order of [cases] regardless of completion order.
  ///
  /// When [cache] is given, each attempt first looks the prompt up in the
  /// cache and only calls [model] on a miss; the response is then written
  /// back. The cache key combines [modelId] and the prompt with a length
  /// prefix, so distinct label and prompt pairs never collide. [modelId]
  /// is also recorded in the report. A cache read that throws is treated
  /// as a miss. A cache write that throws marks the attempt with a model
  /// error (the output is kept, no checks run) and the run continues, so
  /// a broken cache surfaces in the report instead of aborting it.
  ///
  /// When [repeat] is greater than 1, each case runs that many times
  /// (sequentially within the case) and the report exposes a flakiness
  /// rate. Combining [repeat] greater than 1 with a [cache] throws an
  /// [ArgumentError]: after the first attempt warmed the cache, every
  /// later attempt would read the same response and measure nothing.
  ///
  /// A model call that throws marks that attempt with a model error and
  /// does not affect other cases. A check that throws is recorded as an
  /// error result on that check.
  ///
  /// Identical prompts in different cases are not deduplicated while in
  /// flight; each case calls the model itself. Deduplication is planned
  /// for a later release.
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
    if (repeat > 1 && cache != null) {
      throw ArgumentError(
        'repeat > 1 cannot be combined with a cache: after the first '
        'attempt warmed the cache, every later attempt would read the '
        'same response and measure nothing. Run flakiness measurements '
        'without a cache.',
      );
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
    final label = modelId ?? '';
    final key = '${label.length}:$label\n${evalCase.prompt}';
    String? output;
    var fromCache = false;
    if (cache != null) {
      try {
        output = await cache.read(key);
      } catch (_) {
        output = null;
      }
      fromCache = output != null;
    }
    if (output == null) {
      try {
        output = await model(evalCase.prompt);
      } catch (e, stackTrace) {
        stopwatch.stop();
        return AttemptResult(
          output: '',
          checks: const [],
          latency: stopwatch.elapsed,
          fromCache: false,
          modelError: describeError('model call threw', e, stackTrace),
        );
      }
      stopwatch.stop();
      if (cache != null) {
        try {
          await cache.write(key, output);
        } catch (e, stackTrace) {
          return AttemptResult(
            output: output,
            checks: const [],
            latency: stopwatch.elapsed,
            fromCache: false,
            modelError: describeError('cache write failed', e, stackTrace),
          );
        }
      }
    } else {
      stopwatch.stop();
    }
    final outcomes = <CheckOutcome>[];
    for (final check in evalCase.checks) {
      CheckResult result;
      try {
        result = await check.evaluate(output);
      } catch (e, stackTrace) {
        result = CheckResult.error(describeError('check threw', e, stackTrace));
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
