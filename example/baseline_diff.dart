// Two runs at the same pass rate, and the thing a threshold cannot see.
//
//   dart run example/baseline_diff.dart
//
// The README makes this argument with a picture and no runnable code: a gate
// on "75% or better" is blind to a run where one case broke and another was
// fixed, because the rate did not move. A baseline holds the *identity* of
// what passed, so the diff can name both.
//
// The model here answers from a script, so there is no key, no network, and
// the same output every time. The two scripts differ in exactly two answers.
import 'dart:convert';

import 'package:llm_eval/llm_eval.dart';

/// The suite. Four cases, one of which is about to change in each direction.
EvalSuite buildSuite() => EvalSuite([
  EvalCase(
    id: 'shipping-eta',
    prompt: 'When does standard shipping arrive?',
    checks: [Check.contains('business days')],
  ),
  EvalCase(
    id: 'refund-policy',
    prompt: 'How long do I have to return something?',
    checks: [Check.contains('30 days')],
  ),
  EvalCase(
    id: 'store-hours',
    prompt: 'What time do you close?',
    checks: [Check.contains('6pm')],
  ),
  EvalCase(
    id: 'gift-wrap',
    prompt: 'Do you gift wrap?',
    checks: [Check.contains('yes')],
  ),
]);

/// The model before the prompt change: shipping is wrong, refunds are right.
Future<String> before(String prompt) async {
  if (prompt.contains('shipping')) return 'It arrives soon.';
  if (prompt.contains('return')) return 'You have 30 days to return it.';
  if (prompt.contains('close')) return 'We close at 6pm.';
  return 'Yes, we gift wrap.';
}

/// After. Shipping was fixed and refunds broke, which is the whole point:
/// three of four passed before and three of four pass now.
Future<String> after(String prompt) async {
  if (prompt.contains('shipping')) return 'Two to five business days.';
  if (prompt.contains('return')) return 'Returns are accepted for a while.';
  if (prompt.contains('close')) return 'We close at 6pm.';
  return 'Yes, we gift wrap.';
}

void main() async {
  final suite = buildSuite();

  final accepted = await suite.run(before, modelId: 'demo-v1');
  final current = await suite.run(after, modelId: 'demo-v2');

  print('');
  print('the number a threshold looks at');
  print(
    '  accepted run: ${(accepted.passRate * 100).toStringAsFixed(0)}%'
    '   this run: ${(current.passRate * 100).toStringAsFixed(0)}%',
  );
  print('  a gate on "75% or better" passes both, and says nothing happened.');
  print('');

  // A baseline is recorded from the run you were happy with, and in a real
  // project it is committed. Round-tripping it through JSON here is what that
  // looks like: the file on disk is this string.
  final baseline = EvalBaseline.fromReport(accepted);
  final onDisk = jsonEncode(baseline.toJson());
  final reloaded = EvalBaseline.fromJson(
    jsonDecode(onDisk) as Map<String, Object?>,
  );

  final diff = diffAgainstBaseline(current, reloaded);

  print('what the baseline sees');
  for (final change in diff.regressions) {
    print('  broke:  ${change.id}  — ${change.detail}');
  }
  for (final change in diff.fixes) {
    print('  fixed:  ${change.id}  — ${change.detail}');
  }
  for (final change in diff.scoreDrops) {
    print('  slipped: ${change.id}  — ${change.detail}');
  }
  for (final change in diff.newCases) {
    print('  new:    ${change.id}');
  }
  for (final change in diff.removedCases) {
    print('  gone:   ${change.id}  — no longer in the suite');
  }
  print('');

  // A regression is the thing to fail on. A fix is not, and neither is a case
  // that only just appeared -- gating on those would make adding a test a
  // build failure.
  if (diff.regressions.isNotEmpty) {
    print(
      'gate: FAIL — ${diff.regressions.length} case(s) that used to pass '
      'no longer do',
    );
    print('');
    print('The rate did not move. Without the baseline this run ships.');
  } else {
    print('gate: PASS — nothing that passed before is failing now');
  }
}
