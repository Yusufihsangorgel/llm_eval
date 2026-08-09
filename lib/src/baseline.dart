import 'dart:convert';

import 'eval_report.dart';

/// What a case looked like on a run you were happy with.
class BaselineCase {
  /// Creates a [BaselineCase].
  const BaselineCase({
    required this.id,
    required this.passed,
    required this.flaky,
    required this.checkScores,
  });

  /// The case id, matched across runs.
  final String id;

  /// Whether every attempt passed every check.
  final bool passed;

  /// Whether the attempts disagreed with each other.
  final bool flaky;

  /// The score each check reported, keyed by the check's description.
  ///
  /// A check with no score is absent rather than zero, which keeps a
  /// pass/fail check from looking like a score that fell to the floor.
  final Map<String, double> checkScores;

  /// Reads a case out of the `cases` list of [EvalReport.toJson].
  factory BaselineCase.fromReportJson(Map<String, Object?> json) {
    final scores = <String, double>{};
    for (final attempt in (json['attempts'] as List? ?? const [])) {
      for (final check in ((attempt as Map)['checks'] as List? ?? const [])) {
        final c = check as Map;
        final score = c['score'];
        if (score is num) {
          final key = c['description'] as String? ?? '';
          // Several attempts of one case each score the same check. The lowest
          // is the one a gate should remember, because it is the one that
          // would have failed a threshold.
          final existing = scores[key];
          final value = score.toDouble();
          if (existing == null || value < existing) scores[key] = value;
        }
      }
    }
    return BaselineCase(
      id: json['id'] as String,
      passed: json['passed'] as bool? ?? false,
      flaky: json['flaky'] as bool? ?? false,
      checkScores: scores,
    );
  }

  /// This case as JSON.
  Map<String, Object?> toJson() => {
    'id': id,
    'passed': passed,
    'flaky': flaky,
    if (checkScores.isNotEmpty) 'checkScores': checkScores,
  };

  /// Reads a case back from [toJson].
  factory BaselineCase.fromJson(Map<String, Object?> json) => BaselineCase(
    id: json['id'] as String,
    passed: json['passed'] as bool? ?? false,
    flaky: json['flaky'] as bool? ?? false,
    checkScores: {
      for (final e in (json['checkScores'] as Map? ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    },
  );
}

/// A run you were happy with, kept so the next one can be compared to it.
///
/// A pass-rate threshold cannot see composition. Nine of ten passing before
/// and nine of ten passing now is the same number whether nothing moved or one
/// case broke while another was fixed. A baseline holds the identity of what
/// passed, so the second case is a regression and reads like one.
class EvalBaseline {
  /// Creates an [EvalBaseline].
  const EvalBaseline({required this.cases, this.modelId});

  /// The cases, keyed by id.
  final Map<String, BaselineCase> cases;

  /// The model the baseline was recorded against, when the report named one.
  ///
  /// Comparing across models is allowed and reported, rather than refused: a
  /// deliberate model swap is exactly when you want to see what moved.
  final String? modelId;

  /// Captures [report] as a baseline.
  factory EvalBaseline.fromReport(EvalReport report) {
    final json = report.toJson();
    final list = (json['cases'] as List? ?? const []);
    return EvalBaseline(
      modelId: json['modelId'] as String?,
      cases: {
        for (final c in list)
          (c as Map)['id'] as String: BaselineCase.fromReportJson(
            c.cast<String, Object?>(),
          ),
      },
    );
  }

  /// This baseline as JSON, ready for `File.writeAsString`.
  Map<String, Object?> toJson() => {
    'version': 1,
    if (modelId != null) 'modelId': modelId,
    'cases': [for (final c in cases.values) c.toJson()],
  };

  /// Reads a baseline back from [toJson].
  factory EvalBaseline.fromJson(Map<String, Object?> json) {
    final list = (json['cases'] as List? ?? const []);
    return EvalBaseline(
      modelId: json['modelId'] as String?,
      cases: {
        for (final c in list)
          (c as Map)['id'] as String: BaselineCase.fromJson(
            c.cast<String, Object?>(),
          ),
      },
    );
  }

  /// This baseline as the JSON text to commit next to your tests.
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Reads a baseline from the text [toJsonString] wrote.
  factory EvalBaseline.parse(String source) =>
      EvalBaseline.fromJson(jsonDecode(source) as Map<String, Object?>);
}

/// One case that moved between a baseline and a run.
class CaseChange {
  /// Creates a [CaseChange].
  const CaseChange({required this.id, required this.detail});

  /// The case id.
  final String id;

  /// What moved, in one line.
  final String detail;

  @override
  String toString() => '$id: $detail';
}

/// What changed between a baseline and a later run.
class EvalDiff {
  /// Creates an [EvalDiff].
  const EvalDiff({
    required this.regressions,
    required this.fixes,
    required this.scoreDrops,
    required this.newCases,
    required this.removedCases,
    required this.becameFlaky,
    this.baselineModelId,
    this.currentModelId,
  });

  /// Cases that passed in the baseline and do not pass now.
  final List<CaseChange> regressions;

  /// Cases that failed in the baseline and pass now.
  final List<CaseChange> fixes;

  /// Checks whose score fell by more than the tolerance, while still passing.
  final List<CaseChange> scoreDrops;

  /// Cases in the run that the baseline had never seen.
  final List<CaseChange> newCases;

  /// Cases in the baseline that the run no longer has.
  ///
  /// A deleted case is not a pass. Removing the test that was failing moves the
  /// pass rate the same way fixing it does, and only this list tells them
  /// apart.
  final List<CaseChange> removedCases;

  /// Cases that were steady and now disagree between attempts.
  final List<CaseChange> becameFlaky;

  /// The model the baseline was recorded against.
  final String? baselineModelId;

  /// The model this run used.
  final String? currentModelId;

  /// Whether anything a gate should stop for moved.
  ///
  /// Fixes and new cases are not regressions. A removed case is, because it
  /// hides a failure rather than resolving one.
  bool get hasRegressions =>
      regressions.isNotEmpty ||
      scoreDrops.isNotEmpty ||
      removedCases.isNotEmpty ||
      becameFlaky.isNotEmpty;

  /// Whether the run and the baseline name different models.
  bool get modelChanged =>
      baselineModelId != null &&
      currentModelId != null &&
      baselineModelId != currentModelId;

  /// The diff as a block for a CI log.
  String toMarkdown() {
    final b = StringBuffer('## Baseline diff\n\n');
    if (modelChanged) {
      b.writeln(
        'Model changed: `$baselineModelId` to `$currentModelId`. '
        'Everything below is measured across that change.\n',
      );
    }
    void section(String title, List<CaseChange> items) {
      if (items.isEmpty) return;
      b.writeln('### $title (${items.length})\n');
      for (final c in items) {
        b.writeln('- `${c.id}`: ${c.detail}');
      }
      b.writeln();
    }

    section('Regressions', regressions);
    section('Removed cases', removedCases);
    section('Became flaky', becameFlaky);
    section('Score drops', scoreDrops);
    section('Fixed', fixes);
    section('New', newCases);
    if (!hasRegressions && fixes.isEmpty && newCases.isEmpty) {
      b.writeln('Nothing moved.');
    }
    return b.toString();
  }
}

/// Compares [report] against [baseline].
///
/// [scoreTolerance] is how far a score may fall before it counts as a drop.
/// The default allows small model-to-model noise while still catching a check
/// that quietly halved.
EvalDiff diffAgainstBaseline(
  EvalReport report,
  EvalBaseline baseline, {
  double scoreTolerance = 0.05,
}) {
  final current = EvalBaseline.fromReport(report);
  final regressions = <CaseChange>[];
  final fixes = <CaseChange>[];
  final scoreDrops = <CaseChange>[];
  final newCases = <CaseChange>[];
  final removedCases = <CaseChange>[];
  final becameFlaky = <CaseChange>[];

  for (final entry in current.cases.entries) {
    final now = entry.value;
    final before = baseline.cases[entry.key];
    if (before == null) {
      newCases.add(
        CaseChange(
          id: entry.key,
          detail: now.passed ? 'new, passing' : 'new, failing',
        ),
      );
      continue;
    }
    if (before.passed && !now.passed) {
      regressions.add(
        CaseChange(
          id: entry.key,
          detail: now.flaky
              ? 'was passing, now fails on some attempts'
              : 'was passing, now failing',
        ),
      );
    } else if (!before.passed && now.passed) {
      fixes.add(CaseChange(id: entry.key, detail: 'was failing, now passing'));
    }
    // Reported alongside a regression rather than instead of it. A case that
    // went from steady to intermittent needs a different fix than one that
    // simply broke, and only this line says which happened.
    if (!before.flaky && now.flaky) {
      becameFlaky.add(
        CaseChange(id: entry.key, detail: 'attempts no longer agree'),
      );
    }
    for (final s in before.checkScores.entries) {
      final after = now.checkScores[s.key];
      if (after == null) continue;
      final drop = s.value - after;
      if (drop > scoreTolerance) {
        scoreDrops.add(
          CaseChange(
            id: entry.key,
            detail:
                '"${s.key}" fell ${drop.toStringAsFixed(2)} '
                '(${s.value.toStringAsFixed(2)} to ${after.toStringAsFixed(2)})',
          ),
        );
      }
    }
  }

  for (final id in baseline.cases.keys) {
    if (!current.cases.containsKey(id)) {
      removedCases.add(
        CaseChange(id: id, detail: 'in the baseline, missing from this run'),
      );
    }
  }

  return EvalDiff(
    regressions: regressions,
    fixes: fixes,
    scoreDrops: scoreDrops,
    newCases: newCases,
    removedCases: removedCases,
    becameFlaky: becameFlaky,
    baselineModelId: baseline.modelId,
    currentModelId: current.modelId,
  );
}
