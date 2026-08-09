import 'package:llm_eval/llm_eval.dart';
import 'package:test/test.dart';

/// A check with a controllable verdict and score, so a diff can be driven
/// without a model.
class _Fixed implements Check {
  _Fixed(
    this.description,
    this._pass, {
    double? score,
    double? alternateScore,
    this.alternate = false,
  }) : _score = score,
       _alternateScore = alternateScore;

  @override
  final String description;
  final bool _pass;
  final double? _score;

  /// Used by the second and later attempts, so one case can score itself
  /// differently across a repeat.
  final double? _alternateScore;

  /// Flips its verdict on every call, which is what a flaky case looks like
  /// across repeated attempts.
  final bool alternate;
  int _calls = 0;

  @override
  CheckResult evaluate(String output) {
    final n = _calls++;
    final pass = alternate ? n.isEven : _pass;
    final score = (n > 0 && _alternateScore != null) ? _alternateScore : _score;
    return pass
        ? CheckResult.pass(score: score)
        : CheckResult.fail(score: score);
  }
}

Future<EvalReport> run(
  List<String> ids, {
  Set<String> failing = const {},
  Map<String, double> scores = const {},
  double? alternateScore,
  Set<String> flaky = const {},
  String? modelId,
  int repeat = 1,
}) {
  return EvalSuite(
    [
      for (final id in ids)
        EvalCase(
          id: id,
          prompt: id,
          checks: [
            _Fixed(
              'answers $id',
              !failing.contains(id),
              score: scores[id],
              alternateScore: alternateScore,
              alternate: flaky.contains(id),
            ),
          ],
        ),
    ],
  ).run((prompt) async => 'reply to $prompt', repeat: repeat, modelId: modelId);
}

void main() {
  test('a steady run diffs to nothing', () async {
    final first = await run(['a', 'b', 'c']);
    final diff = diffAgainstBaseline(
      await run(['a', 'b', 'c']),
      EvalBaseline.fromReport(first),
    );
    expect(diff.hasRegressions, isFalse);
    expect(diff.toMarkdown(), contains('Nothing moved'));
  });

  test('a swap at the same pass rate is a regression', () async {
    // The case a pass-rate threshold cannot see: two of three passing before
    // and after, and something broke in between.
    final before = await run(['a', 'b', 'c'], failing: {'c'});
    final after = await run(['a', 'b', 'c'], failing: {'a'});

    expect(after.passRate, before.passRate);
    final diff = diffAgainstBaseline(after, EvalBaseline.fromReport(before));

    expect(diff.hasRegressions, isTrue);
    expect(diff.regressions.map((c) => c.id), ['a']);
    expect(diff.fixes.map((c) => c.id), ['c']);
  });

  test('deleting the failing case is not a fix', () async {
    final before = await run(['a', 'b'], failing: {'b'});
    final after = await run(['a']);

    expect(after.passRate, greaterThan(before.passRate));
    final diff = diffAgainstBaseline(after, EvalBaseline.fromReport(before));

    expect(diff.hasRegressions, isTrue);
    expect(diff.removedCases.map((c) => c.id), ['b']);
    expect(diff.regressions, isEmpty);
  });

  test(
    'a score past the tolerance is caught while the case still passes',
    () async {
      final before = await run(['a'], scores: {'a': 0.90});
      final after = await run(['a'], scores: {'a': 0.60});

      expect(after.passRate, 1.0);
      final diff = diffAgainstBaseline(after, EvalBaseline.fromReport(before));

      expect(diff.hasRegressions, isTrue);
      expect(diff.scoreDrops.single.detail, contains('0.90 to 0.60'));
    },
  );

  test('a small score move stays under the tolerance', () async {
    final before = await run(['a'], scores: {'a': 0.90});
    final diff = diffAgainstBaseline(
      await run(['a'], scores: {'a': 0.88}),
      EvalBaseline.fromReport(before),
    );
    expect(diff.scoreDrops, isEmpty);
    expect(diff.hasRegressions, isFalse);
  });

  test('a case that starts disagreeing with itself is caught', () async {
    final before = await run(['a'], repeat: 2);
    final diff = diffAgainstBaseline(
      await run(['a'], repeat: 2, flaky: {'a'}),
      EvalBaseline.fromReport(before),
    );
    expect(diff.becameFlaky.map((c) => c.id), ['a']);
    expect(diff.hasRegressions, isTrue);
  });

  test('flakiness alone stops the gate, with no pass-to-fail change', () async {
    // A case that was failing steadily and now fails intermittently never
    // crosses from passing to failing, so nothing else in the diff fires. The
    // gate has to stop for it anyway: intermittent is worse to debug than
    // broken.
    final before = await run(['a'], failing: {'a'}, repeat: 2);
    final diff = diffAgainstBaseline(
      await run(['a'], repeat: 2, flaky: {'a'}),
      EvalBaseline.fromReport(before),
    );
    expect(diff.regressions, isEmpty);
    expect(diff.fixes, isEmpty);
    expect(diff.becameFlaky.map((c) => c.id), ['a']);
    expect(diff.hasRegressions, isTrue);
  });

  test('a score is remembered at its worst attempt', () async {
    // Two attempts of one case score the same check differently. The baseline
    // keeps the lower one, because that is the number a threshold would have
    // tripped on. Keeping the last would let a bad attempt hide behind a good
    // one that happened to run second.
    final before = await run(['a'], scores: {'a': 0.90}, repeat: 2);
    expect(before.results.single.attempts, hasLength(2));

    final baseline = EvalBaseline.fromReport(
      await run(['a'], scores: {'a': 0.40}, alternateScore: 0.95, repeat: 2),
    );
    expect(baseline.cases['a']!.checkScores['answers a'], 0.40);

    // And the diff reads off that worst value rather than the friendly one.
    final diff = diffAgainstBaseline(
      await run(['a'], scores: {'a': 0.90}, repeat: 2),
      baseline,
    );
    expect(diff.scoreDrops, isEmpty);
    final reverse = diffAgainstBaseline(
      await run(['a'], scores: {'a': 0.20}, repeat: 2),
      baseline,
    );
    expect(reverse.scoreDrops.single.detail, contains('0.40 to 0.20'));
  });

  test('a new case is reported and does not fail the gate', () async {
    final before = await run(['a']);
    final diff = diffAgainstBaseline(
      await run(['a', 'b']),
      EvalBaseline.fromReport(before),
    );
    expect(diff.newCases.map((c) => c.id), ['b']);
    expect(diff.hasRegressions, isFalse);
  });

  test('a baseline survives the round trip through JSON', () async {
    final baseline = EvalBaseline.fromReport(
      await run(['a', 'b'], failing: {'b'}, scores: {'a': 0.75}),
    );
    final reloaded = EvalBaseline.parse(baseline.toJsonString());

    expect(reloaded.cases.keys, baseline.cases.keys);
    expect(reloaded.cases['b']!.passed, isFalse);
    expect(reloaded.cases['a']!.checkScores['answers a'], 0.75);

    final diff = diffAgainstBaseline(await run(['a', 'b']), reloaded);
    expect(diff.fixes.map((c) => c.id), ['b']);
  });

  test('a model change is reported rather than refused', () async {
    final before = await run(['a'], modelId: 'old');
    final diff = diffAgainstBaseline(
      await run(['a'], modelId: 'new'),
      EvalBaseline.fromReport(before),
    );
    expect(diff.modelChanged, isTrue);
    expect(diff.toMarkdown(), contains('`old` to `new`'));
  });
}
