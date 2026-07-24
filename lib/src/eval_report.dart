import 'check_result.dart';

/// The verdict of one check within an attempt.
final class CheckOutcome {
  /// Creates an outcome pairing a check [description] with its [result].
  const CheckOutcome({required this.description, required this.result});

  /// The description of the check that produced [result].
  final String description;

  /// The verdict.
  final CheckResult result;
}

/// One execution of a case: a model output and its check verdicts.
final class AttemptResult {
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
  /// Cache write time and check evaluation time are not included.
  final Duration latency;

  /// Whether the model-under-test output came from the response cache.
  ///
  /// This reflects only the call `EvalSuite.run` makes. A nested model
  /// call, such as the judge in a `Check.judge`, runs inside a check and
  /// has its own cache path through `ResponseCache.wrap`; it is not folded
  /// in here. So a cached attempt whose judge was left unwrapped still
  /// called the judge, and the Markdown report's `cached` column describes
  /// the model under test, not any nested judge.
  final bool fromCache;

  /// The error thrown by the model call or the cache write, or null when
  /// the output was obtained (and, with a cache, stored) successfully.
  final String? modelError;

  /// Whether the model call succeeded and every check passed.
  bool get passed => modelError == null && checks.every((c) => c.result.passed);

  /// Whether the model call failed or any check produced an error result.
  bool get hasError =>
      modelError != null || checks.any((c) => c.result.isError);
}

/// All attempts of one case.
final class CaseResult {
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
final class EvalReport {
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

  /// The number of cases with a model error or an errored check; see
  /// [CaseResult.hasError].
  ///
  /// Errors mean the harness could not produce a verdict, so treat any
  /// nonzero value as a failed run in CI.
  int get errorCount => results.where((r) => r.hasError).length;

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
          'hasError': r.hasError,
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

  /// Renders the report as a JUnit XML document, the format CI systems read
  /// to show test results in their own UI.
  ///
  /// Write it where your CI expects test reports (GitHub Actions, GitLab,
  /// Jenkins, CircleCI and Buildkite all consume this) and each eval case
  /// shows up as a test, with failing ones expanded to the checks that failed
  /// and the model output that failed them:
  ///
  /// ```dart
  /// File('eval-results.xml').writeAsStringSync(report.toJUnitXml());
  /// ```
  ///
  /// A case with a model error or an errored check becomes an `<error>`, any
  /// other non-passing case a `<failure>`, and a flaky case counts as failing
  /// because [CaseResult.passed] requires every attempt to pass. Times are the
  /// summed attempt latencies in seconds.
  ///
  /// Model output is arbitrary text, so it is XML-escaped and characters that
  /// XML 1.0 does not allow at all are dropped rather than smuggled through;
  /// one stray control byte would otherwise make a parser reject the whole
  /// document.
  String toJUnitXml() {
    final suite = modelId ?? 'llm_eval';
    // A test case is an error or a failure, never both, so classify once.
    final errors = results.where((r) => r.hasError).length;
    final failures = results.where((r) => !r.hasError && !r.passed).length;
    final total = results.fold<double>(0, (sum, r) => sum + _seconds(r));

    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<testsuites name="llm_eval" tests="${results.length}" '
        'failures="$failures" errors="$errors" '
        'time="${total.toStringAsFixed(3)}">',
      )
      ..writeln(
        '  <testsuite name="${_xml(suite)}" tests="${results.length}" '
        'failures="$failures" errors="$errors" '
        'time="${total.toStringAsFixed(3)}">',
      );

    for (final r in results) {
      final head =
          '    <testcase name="${_xml(r.caseId)}" '
          'classname="${_xml(suite)}" '
          'time="${_seconds(r).toStringAsFixed(3)}"';
      if (r.passed) {
        b.writeln('$head/>');
        continue;
      }
      final tag = r.hasError ? 'error' : 'failure';
      b
        ..writeln('$head>')
        ..writeln('      <$tag message="${_xml(_shortReason(r))}">')
        ..writeln(_xml(_caseDetails(r)))
        ..writeln('      </$tag>')
        ..writeln('    </testcase>');
    }

    b
      ..writeln('  </testsuite>')
      ..writeln('</testsuites>');
    return b.toString();
  }

  static double _seconds(CaseResult r) =>
      r.attempts.fold<int>(0, (sum, a) => sum + a.latency.inMicroseconds) /
      1000000;

  /// The one-line reason shown in the CI UI next to the case name.
  static String _shortReason(CaseResult r) {
    for (final a in r.attempts) {
      if (a.modelError != null) return 'model error: ${a.modelError}';
      for (final c in a.checks) {
        if (c.result.isError) {
          return 'check errored: ${c.description}: ${c.result.error}';
        }
      }
    }
    final failed = r.attempts
        .expand((a) => a.checks)
        .where((c) => !c.result.passed)
        .map((c) => c.description)
        .toSet();
    if (r.isFlaky) {
      final passed = r.attempts.where((a) => a.passed).length;
      return 'flaky: $passed of ${r.attempts.length} attempts passed '
          '(${failed.join(', ')})';
    }
    return failed.isEmpty
        ? 'case did not pass'
        : 'failed: ${failed.join(', ')}';
  }

  /// The body of the failure element: what failed, and what the model said.
  static String _caseDetails(CaseResult r) {
    final b = StringBuffer();
    for (var i = 0; i < r.attempts.length; i++) {
      final a = r.attempts[i];
      if (r.attempts.length > 1) b.writeln('attempt ${i + 1}:');
      if (a.modelError != null) {
        b.writeln('  model error: ${a.modelError}');
        continue;
      }
      for (final c in a.checks) {
        if (c.result.passed && !c.result.isError) continue;
        b.writeln(
          '  ${c.result.isError ? 'error' : 'failed'}: ${c.description}',
        );
        if (c.result.detail.isNotEmpty) b.writeln('    ${c.result.detail}');
        if (c.result.error != null) b.writeln('    ${c.result.error}');
      }
      b.writeln('  output: ${a.output}');
    }
    return b.toString();
  }

  /// Escapes [s] for XML and drops characters XML 1.0 does not permit.
  static String _xml(String s) {
    final b = StringBuffer();
    for (final rune in s.runes) {
      final allowed =
          rune == 0x9 ||
          rune == 0xA ||
          rune == 0xD ||
          (rune >= 0x20 && rune <= 0xD7FF) ||
          (rune >= 0xE000 && rune <= 0xFFFD) ||
          (rune >= 0x10000 && rune <= 0x10FFFF);
      if (!allowed) continue;
      switch (rune) {
        case 0x26:
          b.write('&amp;');
        case 0x3C:
          b.write('&lt;');
        case 0x3E:
          b.write('&gt;');
        case 0x22:
          b.write('&quot;');
        case 0x27:
          b.write('&apos;');
        default:
          b.writeCharCode(rune);
      }
    }
    return b.toString();
  }

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
