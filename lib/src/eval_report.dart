import 'check_result.dart';

/// The verdict of one check within an attempt.
class CheckOutcome {
  /// Creates an outcome pairing a check [description] with its [result].
  const CheckOutcome({required this.description, required this.result});

  /// The description of the check that produced [result].
  final String description;

  /// The verdict.
  final CheckResult result;
}

/// One execution of a case: a model output and its check verdicts.
class AttemptResult {
  /// Creates an attempt result.
  const AttemptResult({
    required this.output,
    required this.checks,
    required this.latency,
    required this.fromCache,
    this.modelError,
  });

  /// The model output, or an empty string when [modelError] is set.
  final String output;

  /// Check verdicts in the order the checks were declared.
  final List<CheckOutcome> checks;

  /// Time spent obtaining the output (model call or cache read).
  ///
  /// Check evaluation time is not included.
  final Duration latency;

  /// Whether the output came from the response cache.
  final bool fromCache;

  /// The error thrown by the model call, or null when the call succeeded.
  final String? modelError;

  /// Whether the model call succeeded and every check passed.
  bool get passed => modelError == null && checks.every((c) => c.result.passed);

  /// Whether the model call failed or any check produced an error result.
  bool get hasError =>
      modelError != null || checks.any((c) => c.result.isError);
}

/// All attempts of one case.
class CaseResult {
  /// Creates a case result.
  const CaseResult({required this.caseId, required this.attempts});

  /// The id of the case this result belongs to.
  final String caseId;

  /// One entry per attempt; the length equals the `repeat` argument of
  /// the run.
  final List<AttemptResult> attempts;

  /// Whether every attempt passed.
  bool get passed => attempts.every((a) => a.passed);

  /// Whether the attempts disagree: at least one passed and at least one
  /// did not.
  ///
  /// Always false when there is a single attempt.
  bool get isFlaky =>
      attempts.any((a) => a.passed) && attempts.any((a) => !a.passed);

  /// Whether any attempt had a model error or an errored check.
  bool get hasError => attempts.any((a) => a.hasError);
}

/// The result of an `EvalSuite` run.
///
/// Normally produced by `EvalSuite.run`. The constructor is public so
/// tests and tools can build reports directly.
class EvalReport {
  /// Creates a report over [results].
  const EvalReport({required this.results, this.repeat = 1, this.modelId});

  /// Per-case results, in the order the cases appear in the suite.
  final List<CaseResult> results;

  /// How many times each case was run.
  final int repeat;

  /// The model label the run was tagged with, if any.
  final String? modelId;

  /// The number of cases in which every attempt passed.
  int get passedCount => results.where((r) => r.passed).length;

  /// The number of flaky cases; see [CaseResult.isFlaky].
  int get flakyCount => results.where((r) => r.isFlaky).length;

  /// The fraction of cases that passed, between 0.0 and 1.0.
  ///
  /// A case counts as passed only when every attempt passed, so a flaky
  /// case counts as failed. An empty report has a pass rate of 1.0.
  double get passRate => results.isEmpty ? 1.0 : passedCount / results.length;

  /// The fraction of flaky cases, between 0.0 and 1.0.
  ///
  /// Always 0.0 when [repeat] is 1.
  double get flakinessRate =>
      results.isEmpty ? 0.0 : flakyCount / results.length;

  static double _round(double v) => double.parse(v.toStringAsFixed(4));

  static String _percent(double v) => '${(v * 100).toStringAsFixed(1)}%';

  static String _cell(String s) => s.replaceAll('|', r'\|');

  static String _status(CaseResult r) {
    if (r.hasError) return 'error';
    if (r.isFlaky) return 'flaky';
    return r.passed ? 'pass' : 'fail';
  }

  /// Encodes the report as a JSON-compatible map.
  ///
  /// Rates are rounded to four decimal places so encoded output is
  /// stable across runs with the same results.
  Map<String, Object?> toJson() => {
    'modelId': modelId,
    'repeat': repeat,
    'caseCount': results.length,
    'passedCount': passedCount,
    'passRate': _round(passRate),
    'flakyCount': flakyCount,
    'flakinessRate': _round(flakinessRate),
    'cases': [
      for (final r in results)
        {
          'id': r.caseId,
          'passed': r.passed,
          'flaky': r.isFlaky,
          'attempts': [
            for (final a in r.attempts)
              {
                'output': a.output,
                'passed': a.passed,
                'latencyMs': a.latency.inMilliseconds,
                'fromCache': a.fromCache,
                'modelError': a.modelError,
                'checks': [
                  for (final c in a.checks)
                    {
                      'description': c.description,
                      'passed': c.result.passed,
                      'score': c.result.score,
                      'detail': c.result.detail,
                      'error': c.result.error,
                    },
                ],
              },
          ],
        },
    ],
  };

  /// Renders the report as Markdown, suitable for a CI job summary.
  ///
  /// The summary table describes the first attempt of each case; the
  /// status column and the flakiness line take all attempts into
  /// account. Non-passing cases get a details section listing failing
  /// checks and the model output.
  String toMarkdown() {
    final b = StringBuffer();
    b.writeln('# llm_eval report');
    b.writeln();
    if (modelId != null) b.writeln('- model: `$modelId`');
    b.writeln('- cases: ${results.length}');
    b.writeln(
      '- pass rate: ${_percent(passRate)} ($passedCount/${results.length})',
    );
    if (repeat > 1) {
      b.writeln('- repeat: $repeat');
      b.writeln(
        '- flakiness: ${_percent(flakinessRate)} '
        '($flakyCount/${results.length})',
      );
    }
    if (results.isNotEmpty) {
      b.writeln();
      b.writeln('| case | status | checks | latency | cached |');
      b.writeln('| --- | --- | --- | --- | --- |');
      for (final r in results) {
        final first = r.attempts.first;
        final checksCell = first.modelError != null
            ? '-'
            : '${first.checks.where((c) => c.result.passed).length}'
                  '/${first.checks.length}';
        b.writeln(
          '| ${_cell(r.caseId)} | ${_status(r)} | $checksCell '
          '| ${first.latency.inMilliseconds}ms '
          '| ${first.fromCache ? 'yes' : 'no'} |',
        );
      }
    }
    final failing = results.where((r) => !r.passed);
    if (failing.isNotEmpty) {
      b.writeln();
      b.writeln('## Details');
      for (final r in failing) {
        b.writeln();
        b.writeln('### ${r.caseId}');
        for (var i = 0; i < r.attempts.length; i++) {
          final a = r.attempts[i];
          if (a.passed) continue;
          b.writeln();
          if (r.attempts.length > 1) {
            b.writeln('Attempt ${i + 1}:');
            b.writeln();
          }
          if (a.modelError != null) {
            b.writeln('- model error: ${a.modelError}');
            continue;
          }
          for (final c in a.checks) {
            if (c.result.passed) continue;
            if (c.result.isError) {
              b.writeln('- error: ${c.description} (${c.result.error})');
            } else if (c.result.detail.isEmpty) {
              b.writeln('- fail: ${c.description}');
            } else {
              b.writeln('- fail: ${c.description} (${c.result.detail})');
            }
          }
          b.writeln();
          b.writeln('Output:');
          b.writeln();
          for (final line in a.output.split('\n')) {
            b.writeln('> $line');
          }
        }
      }
    }
    return b.toString();
  }
}
