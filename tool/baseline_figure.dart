// Draws doc/baseline-diff.svg from a diff computed at run time.
//
//   dart run tool/baseline_figure.dart
//   rsvg-convert -w 1600 doc/baseline-diff.svg -o doc/baseline-diff.png
//
// The figure is the argument for keeping a baseline: two runs at the identical
// pass rate, one of which broke something. The numbers and the case names come
// out of a real diff rather than being typed into the drawing.

import 'dart:io';

import 'package:llm_eval/llm_eval.dart';

/// A check whose verdict is fixed, so a run can be scripted.
class _Fixed implements Check {
  _Fixed(this.description, this._pass);

  @override
  final String description;
  final bool _pass;

  @override
  CheckResult evaluate(String output) =>
      _pass ? const CheckResult.pass() : const CheckResult.fail();
}

const cases = ['refund-policy', 'order-status', 'shipping-eta', 'greeting'];

Future<EvalReport> _run(Set<String> failing) => EvalSuite([
  for (final id in cases)
    EvalCase(
      id: id,
      prompt: id,
      checks: [_Fixed('answers the question', !failing.contains(id))],
    ),
]).run((p) async => 'reply', modelId: 'gpt-4o-mini');

void main() async {
  final before = await _run({'shipping-eta'});
  final after = await _run({'refund-policy'});
  final diff = diffAgainstBaseline(after, EvalBaseline.fromReport(before));

  if (before.passRate != after.passRate) {
    stderr.writeln(
      'the two runs must share a pass rate for the figure to say '
      'what it says',
    );
    exitCode = 1;
    return;
  }

  File('doc/baseline-diff.svg').writeAsStringSync(_svg(before.passRate, diff));

  stdout.writeln('pass rate before  ${before.passRate}');
  stdout.writeln('pass rate after   ${after.passRate}');
  stdout.writeln('regressions       ${diff.regressions}');
  stdout.writeln('fixes             ${diff.fixes}');
  stdout.writeln('wrote doc/baseline-diff.svg');
}

String _svg(double rate, EvalDiff diff) {
  const w = 860.0, h = 380.0;
  final pct = '${(rate * 100).round()}%';

  String column(double x, String title, Set<String> failing) {
    final rows = <String>[];
    for (var i = 0; i < cases.length; i++) {
      final id = cases[i];
      final bad = failing.contains(id);
      final y = 118.0 + i * 42;
      rows.add('''
<rect x="$x" y="$y" width="300" height="32" rx="6"
      fill="${bad ? '#fee2e2' : '#ecfdf5'}" stroke="${bad ? '#fca5a5' : '#a7f3d0'}"/>
<text x="${x + 14}" y="${y + 21}" font-size="14" font-family="monospace"
      fill="#111827">$id</text>
<text x="${x + 286}" y="${y + 21}" font-size="14" text-anchor="end"
      fill="${bad ? '#b91c1c' : '#047857'}">${bad ? 'fail' : 'pass'}</text>''');
    }
    return '''
<text x="${x + 150}" y="72" text-anchor="middle" font-size="15"
      font-weight="600" fill="#111827">$title</text>
<text x="${x + 150}" y="94" text-anchor="middle" font-size="13" fill="#6b7280">
  pass rate $pct
</text>
${rows.join('\n')}''';
  }

  final regressed = diff.regressions.map((c) => c.id).toSet();
  final fixed = diff.fixes.map((c) => c.id).toSet();

  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w.toInt()} ${h.toInt()}"
     font-family="-apple-system, Segoe UI, Roboto, sans-serif">
<rect width="100%" height="100%" fill="#ffffff"/>
<text x="40" y="36" font-size="17" font-weight="600" fill="#111827">
  Same pass rate, and one of these runs broke something
</text>
${column(40, 'baseline', {'shipping-eta'})}
${column(500, 'this run', {'refund-policy'})}
<text x="430" y="${118 + 0 * 42 + 21}" text-anchor="middle" font-size="18"
      fill="#b91c1c">&#8594;</text>
<text x="430" y="${118 + 2 * 42 + 21}" text-anchor="middle" font-size="18"
      fill="#047857">&#8594;</text>
<rect x="40" y="300" width="780" height="52" rx="8" fill="#f9fafb"
      stroke="#e5e7eb"/>
<text x="58" y="322" font-size="13" fill="#b91c1c" font-weight="600">
  regression &#183; <tspan font-family="monospace">${regressed.join(', ')}</tspan>
</text>
<text x="58" y="342" font-size="13" fill="#047857" font-weight="600">
  fixed &#183; <tspan font-family="monospace">${fixed.join(', ')}</tspan>
</text>
<text x="802" y="332" font-size="13" text-anchor="end" fill="#6b7280">
  a threshold on $pct sees neither
</text>
</svg>
''';
}
