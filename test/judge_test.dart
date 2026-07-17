import 'package:llm_eval/llm_eval.dart';
import 'package:test/test.dart';

/// Returns a judge that always answers with [response].
ModelCall cannedJudge(String response) =>
    (prompt) async => response;

void main() {
  group('Check.judge', () {
    test('passes when the score is at or above passAt', () async {
      final check = Check.judge(
        judge: cannedJudge('SCORE: 0.8'),
        rubric: 'Mentions Paris.',
      );
      final result = await check.evaluate('Paris is the capital.');
      expect(result.passed, isTrue);
      expect(result.score, 0.8);
    });

    test('a score exactly at passAt passes', () async {
      final check = Check.judge(
        judge: cannedJudge('SCORE: 0.7'),
        rubric: 'anything',
      );
      expect((await check.evaluate('x')).passed, isTrue);
    });

    test('fails when the score is below passAt', () async {
      final check = Check.judge(
        judge: cannedJudge('SCORE: 0.5'),
        rubric: 'anything',
      );
      final result = await check.evaluate('x');
      expect(result.passed, isFalse);
      expect(result.isError, isFalse);
      expect(result.score, 0.5);
    });

    test('respects a custom passAt', () async {
      final check = Check.judge(
        judge: cannedJudge('SCORE: 0.8'),
        rubric: 'anything',
        passAt: 0.9,
      );
      expect((await check.evaluate('x')).passed, isFalse);
    });

    test('rejects a passAt outside 0.0 to 1.0', () {
      expect(
        () => Check.judge(
          judge: cannedJudge('SCORE: 1'),
          rubric: 'anything',
          passAt: 1.5,
        ),
        throwsArgumentError,
      );
    });

    test('parses the score line out of a longer response', () async {
      final check = Check.judge(
        judge: cannedJudge(
          'Let me look at the rubric.\nSCORE: 0.9\nThe answer is correct.',
        ),
        rubric: 'anything',
      );
      final result = await check.evaluate('x');
      expect(result.passed, isTrue);
      expect(result.score, 0.9);
    });

    test('an unparsable judge response is an error, never a pass', () async {
      final check = Check.judge(
        judge: cannedJudge('Looks good to me!'),
        rubric: 'anything',
      );
      final result = await check.evaluate('x');
      expect(result.passed, isFalse);
      expect(result.isError, isTrue);
      expect(result.error, contains('SCORE'));
    });

    test('a score outside 0.0 to 1.0 is an error', () async {
      final check = Check.judge(
        judge: cannedJudge('SCORE: 1.5'),
        rubric: 'anything',
      );
      final result = await check.evaluate('x');
      expect(result.isError, isTrue);
      expect(result.error, contains('outside'));
    });

    test('a throwing judge call is an error', () async {
      final check = Check.judge(
        judge: (prompt) async => throw StateError('judge down'),
        rubric: 'anything',
      );
      final result = await check.evaluate('x');
      expect(result.isError, isTrue);
      expect(result.error, contains('judge down'));
    });

    test('sends the rubric and the graded output to the judge', () async {
      String? seenPrompt;
      final check = Check.judge(
        judge: (prompt) async {
          seenPrompt = prompt;
          return 'SCORE: 1.0';
        },
        rubric: 'The answer names Paris.',
      );
      await check.evaluate('Paris, of course.');
      expect(seenPrompt, contains('The answer names Paris.'));
      expect(seenPrompt, contains('Paris, of course.'));
      expect(seenPrompt, contains('SCORE'));
    });

    test('description names the threshold', () {
      final check = Check.judge(
        judge: cannedJudge('SCORE: 1'),
        rubric: 'anything',
        passAt: 0.9,
      );
      expect(check.description, 'judge score >= 0.9');
    });
  });
}
