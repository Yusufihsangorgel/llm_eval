import 'dart:async';

import 'package:llm_eval/llm_eval.dart';
import 'package:test/test.dart';

/// A check whose [evaluate] throws instead of returning a result.
class ThrowingCheck implements Check {
  @override
  String get description => 'throwing check';

  @override
  FutureOr<CheckResult> evaluate(String output) =>
      throw StateError('bad check');
}

void main() {
  group('EvalSuite.run', () {
    test('keeps result order even when cases finish out of order', () async {
      // The prompt encodes the model delay in milliseconds, so earlier
      // cases finish later.
      Future<String> model(String prompt) async {
        await Future<void>.delayed(Duration(milliseconds: int.parse(prompt)));
        return 'answer $prompt';
      }

      final delays = ['40', '1', '30', '2', '20', '3'];
      final suite = EvalSuite([
        for (var i = 0; i < delays.length; i++)
          EvalCase(
            id: 'case-$i',
            prompt: delays[i],
            checks: [Check.contains('answer')],
          ),
      ]);

      final report = await suite.run(model, concurrency: 4);
      expect(report.results.map((r) => r.caseId), [
        for (var i = 0; i < delays.length; i++) 'case-$i',
      ]);
      for (var i = 0; i < delays.length; i++) {
        expect(report.results[i].attempts.single.output, 'answer ${delays[i]}');
      }
      expect(report.passRate, 1.0);
    });

    test('never runs more than concurrency cases at once', () async {
      var inFlight = 0;
      var maxInFlight = 0;
      Future<String> model(String prompt) async {
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return 'ok';
      }

      final suite = EvalSuite([
        for (var i = 0; i < 8; i++)
          EvalCase(id: 'c$i', prompt: 'p$i', checks: [Check.contains('ok')]),
      ]);
      await suite.run(model, concurrency: 2);
      expect(maxInFlight, 2);
    });

    test('concurrency 1 runs cases in declaration order', () async {
      final calls = <String>[];
      Future<String> model(String prompt) async {
        calls.add(prompt);
        return 'ok';
      }

      final suite = EvalSuite([
        for (var i = 0; i < 4; i++)
          EvalCase(id: 'c$i', prompt: 'p$i', checks: [Check.contains('ok')]),
      ]);
      await suite.run(model, concurrency: 1);
      expect(calls, ['p0', 'p1', 'p2', 'p3']);
    });

    test('a throwing model call errors that case only', () async {
      Future<String> model(String prompt) async {
        if (prompt == 'boom') throw StateError('model down');
        return 'fine';
      }

      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'x', checks: [Check.contains('fine')]),
        EvalCase(id: 'b', prompt: 'boom', checks: [Check.contains('fine')]),
        EvalCase(id: 'c', prompt: 'y', checks: [Check.contains('fine')]),
      ]);
      final report = await suite.run(model);

      expect(report.results[0].passed, isTrue);
      expect(report.results[2].passed, isTrue);

      final failed = report.results[1];
      expect(failed.passed, isFalse);
      expect(failed.hasError, isTrue);
      expect(failed.attempts.single.modelError, contains('model down'));
      expect(failed.attempts.single.checks, isEmpty);
      expect(report.passRate, closeTo(2 / 3, 1e-9));
    });

    test('a throwing check becomes an error outcome for that check', () async {
      final suite = EvalSuite([
        EvalCase(
          id: 'a',
          prompt: 'x',
          checks: [Check.contains('ok'), ThrowingCheck()],
        ),
      ]);
      final report = await suite.run((prompt) async => 'ok');

      final attempt = report.results.single.attempts.single;
      expect(attempt.checks, hasLength(2));
      expect(attempt.checks[0].result.passed, isTrue);
      expect(attempt.checks[1].result.isError, isTrue);
      expect(attempt.checks[1].result.error, contains('bad check'));
      expect(attempt.checks[1].result.error, contains('stack:'));
      expect(attempt.passed, isFalse);
      expect(attempt.hasError, isTrue);
    });

    test('records model latency per attempt', () async {
      Future<String> model(String prompt) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 'ok';
      }

      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'x', checks: [Check.contains('ok')]),
      ]);
      final report = await suite.run(model);
      expect(
        report.results.single.attempts.single.latency,
        greaterThanOrEqualTo(const Duration(milliseconds: 15)),
      );
    });

    test('rejects concurrency and repeat below 1', () async {
      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'x', checks: [Check.contains('ok')]),
      ]);
      Future<String> model(String prompt) async => 'ok';
      expect(() => suite.run(model, concurrency: 0), throwsArgumentError);
      expect(() => suite.run(model, repeat: 0), throwsArgumentError);
    });

    test('an empty suite reports a pass rate of 1.0', () async {
      final report = await EvalSuite([]).run((prompt) async => 'unused');
      expect(report.results, isEmpty);
      expect(report.passRate, 1.0);
      expect(report.flakinessRate, 0.0);
    });
  });

  group('repeat and flakiness', () {
    test('runs each case repeat times', () async {
      var calls = 0;
      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'x', checks: [Check.contains('ok')]),
      ]);
      final report = await suite.run((prompt) async {
        calls++;
        return 'ok';
      }, repeat: 3);
      expect(calls, 3);
      expect(report.results.single.attempts, hasLength(3));
      expect(report.repeat, 3);
    });

    test('detects a case whose attempts disagree', () async {
      final callsPerPrompt = <String, int>{};
      Future<String> model(String prompt) async {
        final n = callsPerPrompt[prompt] = (callsPerPrompt[prompt] ?? 0) + 1;
        if (prompt == 'flaky') return n.isOdd ? 'yes' : 'no';
        return 'yes';
      }

      final suite = EvalSuite([
        EvalCase(id: 'stable', prompt: 'ok', checks: [Check.contains('yes')]),
        EvalCase(id: 'flaky', prompt: 'flaky', checks: [Check.contains('yes')]),
      ]);
      final report = await suite.run(model, repeat: 2);

      expect(report.results[0].isFlaky, isFalse);
      expect(report.results[0].passed, isTrue);
      expect(report.results[1].isFlaky, isTrue);
      expect(report.results[1].passed, isFalse);
      expect(report.flakinessRate, 0.5);
      expect(report.passRate, 0.5);
    });

    test('a stable suite has zero flakiness', () async {
      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'x', checks: [Check.contains('ok')]),
        EvalCase(id: 'b', prompt: 'y', checks: [Check.contains('ok')]),
      ]);
      final report = await suite.run((prompt) async => 'ok', repeat: 3);
      expect(report.flakinessRate, 0.0);
      expect(report.passRate, 1.0);
    });

    test('a case that fails every attempt is failed, not flaky', () async {
      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'x', checks: [Check.contains('missing')]),
      ]);
      final report = await suite.run((prompt) async => 'ok', repeat: 2);
      expect(report.results.single.passed, isFalse);
      expect(report.results.single.isFlaky, isFalse);
      expect(report.flakinessRate, 0.0);
    });
  });

  group('EvalCase', () {
    test('carries metadata without interpreting it', () {
      final evalCase = EvalCase(
        id: 'a',
        prompt: 'x',
        checks: [Check.contains('ok')],
        metadata: {'owner': 'search-team', 'ticket': 42},
      );
      expect(evalCase.metadata['owner'], 'search-team');
      expect(evalCase.metadata['ticket'], 42);
    });
  });
}
