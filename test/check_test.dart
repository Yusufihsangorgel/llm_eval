import 'package:llm_eval/llm_eval.dart';
import 'package:test/test.dart';

void main() {
  group('CheckResult', () {
    test('pass and fail are verdicts, not errors', () {
      const pass = CheckResult.pass(score: 0.9, detail: 'ok');
      expect(pass.passed, isTrue);
      expect(pass.isError, isFalse);
      expect(pass.score, 0.9);

      const fail = CheckResult.fail(detail: 'nope');
      expect(fail.passed, isFalse);
      expect(fail.isError, isFalse);
    });

    test('error carries a message and never passes', () {
      const error = CheckResult.error('broken');
      expect(error.passed, isFalse);
      expect(error.isError, isTrue);
      expect(error.error, 'broken');
      expect(error.score, isNull);
    });
  });

  group('Check.contains', () {
    test('passes case-insensitively by default', () async {
      final result = await Check.contains('PARIS').evaluate('paris is nice');
      expect(result.passed, isTrue);
    });

    test('fails when the needle is absent', () async {
      final result = await Check.contains('paris').evaluate('London calling');
      expect(result.passed, isFalse);
      expect(result.isError, isFalse);
      expect(result.detail, contains('does not contain'));
    });

    test('case-sensitive mode fails on a case mismatch', () async {
      final check = Check.contains('Paris', caseSensitive: true);
      expect((await check.evaluate('paris')).passed, isFalse);
    });

    test('case-sensitive mode passes on an exact match', () async {
      final check = Check.contains('Paris', caseSensitive: true);
      expect((await check.evaluate('Paris')).passed, isTrue);
    });

    test('description names the needle', () {
      expect(Check.contains('paris').description, 'contains "paris"');
      expect(
        Check.contains('paris', caseSensitive: true).description,
        'contains "paris" (case-sensitive)',
      );
    });
  });

  group('Check.notContains', () {
    test('passes when the needle is absent', () async {
      final result = await Check.notContains('error').evaluate('all good');
      expect(result.passed, isTrue);
    });

    test('fails when the needle is present, ignoring case', () async {
      final result = await Check.notContains('error').evaluate('ERROR: no');
      expect(result.passed, isFalse);
      expect(result.detail, contains('output contains'));
    });

    test('case-sensitive mode ignores differently cased needles', () async {
      final check = Check.notContains('Error', caseSensitive: true);
      expect((await check.evaluate('error in lowercase')).passed, isTrue);
    });
  });

  group('Check.matches', () {
    test('passes when the pattern matches', () async {
      final check = Check.matches(RegExp(r'^\d+$'));
      expect((await check.evaluate('12345')).passed, isTrue);
    });

    test('fails when the pattern does not match', () async {
      final check = Check.matches(RegExp(r'^\d+$'));
      final result = await check.evaluate('twelve');
      expect(result.passed, isFalse);
      expect(result.isError, isFalse);
    });

    test('description names the pattern', () {
      expect(Check.matches(RegExp(r'^\d+$')).description, r'matches ^\d+$');
    });
  });

  group('Check.isValidJson', () {
    test('passes on valid JSON', () async {
      final result = await Check.isValidJson().evaluate('{"a": 1}');
      expect(result.passed, isTrue);
    });

    test('fails on invalid JSON', () async {
      final result = await Check.isValidJson().evaluate('not json');
      expect(result.passed, isFalse);
      expect(result.isError, isFalse);
      expect(result.detail, contains('not valid JSON'));
    });

    test('where condition can accept the decoded value', () async {
      final check = Check.isValidJson(
        where: (decoded) => decoded is Map && decoded['a'] == 1,
      );
      expect((await check.evaluate('{"a": 1}')).passed, isTrue);
    });

    test('where condition can reject the decoded value', () async {
      final check = Check.isValidJson(
        where: (decoded) => decoded is Map && decoded['a'] == 2,
      );
      final result = await check.evaluate('{"a": 1}');
      expect(result.passed, isFalse);
      expect(result.isError, isFalse);
    });

    test('a throwing where callback is an error, not a fail', () async {
      final check = Check.isValidJson(
        where: (decoded) => throw StateError('bad callback'),
      );
      final result = await check.evaluate('{"a": 1}');
      expect(result.isError, isTrue);
      expect(result.error, contains('bad callback'));
    });

    test('passes on JSON wrapped in a ```json fence', () async {
      final result = await Check.isValidJson().evaluate(
        '```json\n{"a": 1}\n```',
      );
      expect(result.passed, isTrue);
      expect(result.isError, isFalse);
    });

    test('passes on JSON wrapped in a plain ``` fence', () async {
      final result = await Check.isValidJson().evaluate('```\n{"a": 1}\n```');
      expect(result.passed, isTrue);
    });

    test('passes on a fenced block followed by trailing prose', () async {
      // The common real-world shape: a chat model answers with a fenced
      // JSON block, then adds a sentence of prose after the closing fence.
      final result =
          await Check.isValidJson(
            where: (v) => v is Map && v['city'] == 'Paris',
          ).evaluate(
            '```json\n{\n  "city": "Paris"\n}\n```\n\nThis is the capital of France.',
          );
      expect(result.passed, isTrue);
      expect(result.isError, isFalse);
    });

    test(
      'the where callback receives the value decoded from the fence',
      () async {
        final check = Check.isValidJson(
          where: (decoded) => decoded is Map && decoded['a'] == 2,
        );
        final result = await check.evaluate('```json\n{"a": 1}\n```');
        expect(result.passed, isFalse);
        expect(result.isError, isFalse);
      },
    );

    test(
      'fails when neither the raw output nor a fenced block parses',
      () async {
        final result = await Check.isValidJson().evaluate(
          '```json\nnot json\n```',
        );
        expect(result.passed, isFalse);
        expect(result.isError, isFalse);
        expect(result.detail, contains('not valid JSON'));
      },
    );

    test('fails on plain non-JSON prose with no fence at all', () async {
      final result = await Check.isValidJson().evaluate(
        'Sure, the capital of France is Paris.',
      );
      expect(result.passed, isFalse);
      expect(result.isError, isFalse);
      expect(result.detail, contains('not valid JSON'));
    });
  });

  group('Check.predicate', () {
    test('passes when the function returns true', () async {
      final check = Check.predicate('short output', (o) => o.length < 10);
      expect((await check.evaluate('short')).passed, isTrue);
    });

    test('fails when the function returns false', () async {
      final check = Check.predicate('short output', (o) => o.length < 10);
      final result = await check.evaluate('a very long output indeed');
      expect(result.passed, isFalse);
      expect(result.isError, isFalse);
    });

    test('supports async functions', () async {
      final check = Check.predicate('async', (o) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return o == 'yes';
      });
      expect((await check.evaluate('yes')).passed, isTrue);
      expect((await check.evaluate('no')).passed, isFalse);
    });

    test('a throwing function is an error, not a fail', () async {
      final check = Check.predicate(
        'explodes',
        (o) => throw StateError('boom'),
      );
      final result = await check.evaluate('anything');
      expect(result.isError, isTrue);
      expect(result.error, contains('boom'));
      expect(result.error, contains('explodes'));
    });

    test('uses the given description', () {
      expect(Check.predicate('my rule', (o) => true).description, 'my rule');
    });
  });
}
