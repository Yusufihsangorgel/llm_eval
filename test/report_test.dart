import 'dart:convert';

import 'package:llm_eval/llm_eval.dart';
import 'package:test/test.dart';

/// A report with one passing, one failing, and one errored case.
EvalReport mixedReport() => const EvalReport(
  modelId: 'fake-1',
  results: [
    CaseResult(
      caseId: 'greeting',
      attempts: [
        AttemptResult(
          output: 'Hello there!',
          checks: [
            CheckOutcome(
              description: 'contains "hello"',
              result: CheckResult.pass(),
            ),
            CheckOutcome(
              description: 'does not contain "bye"',
              result: CheckResult.pass(),
            ),
          ],
          latency: Duration(milliseconds: 12),
          fromCache: false,
        ),
      ],
    ),
    CaseResult(
      caseId: 'json',
      attempts: [
        AttemptResult(
          output: 'not json',
          checks: [
            CheckOutcome(
              description: 'is valid JSON',
              result: CheckResult.fail(
                detail: 'not valid JSON: Unexpected character',
              ),
            ),
          ],
          latency: Duration(milliseconds: 30),
          fromCache: true,
        ),
      ],
    ),
    CaseResult(
      caseId: 'broken',
      attempts: [
        AttemptResult(
          output: '',
          checks: [],
          latency: Duration(milliseconds: 5),
          fromCache: false,
          modelError: 'Exception: boom',
        ),
      ],
    ),
  ],
);

/// A report with a single flaky case run twice.
EvalReport flakyReport() => const EvalReport(
  repeat: 2,
  results: [
    CaseResult(
      caseId: 'flaky-case',
      attempts: [
        AttemptResult(
          output: 'yes',
          checks: [
            CheckOutcome(
              description: 'contains "yes"',
              result: CheckResult.pass(),
            ),
          ],
          latency: Duration(milliseconds: 10),
          fromCache: false,
        ),
        AttemptResult(
          output: 'no',
          checks: [
            CheckOutcome(
              description: 'contains "yes"',
              result: CheckResult.fail(detail: 'output does not contain "yes"'),
            ),
          ],
          latency: Duration(milliseconds: 11),
          fromCache: false,
        ),
      ],
    ),
  ],
);

void main() {
  group('EvalReport.toMarkdown', () {
    test('renders pass, fail, and error cases (golden)', () {
      const expected = '''
# llm_eval report

- model: `fake-1`
- cases: 3
- pass rate: 33.3% (1/3)

| case | status | checks | latency | cached |
| --- | --- | --- | --- | --- |
| greeting | pass | 2/2 | 12ms | no |
| json | fail | 0/1 | 30ms | yes |
| broken | error | - | 5ms | no |

## Details

### json

- fail: is valid JSON (not valid JSON: Unexpected character)

Output:

> not json

### broken

- model error: Exception: boom
''';
      expect(mixedReport().toMarkdown(), expected);
    });

    test('renders repeat and flakiness (golden)', () {
      const expected = '''
# llm_eval report

- cases: 1
- pass rate: 0.0% (0/1)
- repeat: 2
- flakiness: 100.0% (1/1)

| case | status | checks | latency | cached |
| --- | --- | --- | --- | --- |
| flaky-case | flaky | 1/1 | 10ms | no |

## Details

### flaky-case

Attempt 2:

- fail: contains "yes" (output does not contain "yes")

Output:

> no
''';
      expect(flakyReport().toMarkdown(), expected);
    });

    test('escapes pipes in case ids', () {
      const report = EvalReport(
        results: [
          CaseResult(
            caseId: 'a|b',
            attempts: [
              AttemptResult(
                output: 'ok',
                checks: [],
                latency: Duration(milliseconds: 1),
                fromCache: false,
              ),
            ],
          ),
        ],
      );
      expect(report.toMarkdown(), contains(r'a\|b'));
    });

    test('an errored case outranks flaky in the status column', () {
      const report = EvalReport(
        repeat: 2,
        results: [
          CaseResult(
            caseId: 'sometimes-broken',
            attempts: [
              AttemptResult(
                output: 'ok',
                checks: [
                  CheckOutcome(
                    description: 'contains "ok"',
                    result: CheckResult.pass(),
                  ),
                ],
                latency: Duration(milliseconds: 1),
                fromCache: false,
              ),
              AttemptResult(
                output: '',
                checks: [],
                latency: Duration(milliseconds: 1),
                fromCache: false,
                modelError: 'Exception: boom',
              ),
            ],
          ),
        ],
      );
      expect(report.toMarkdown(), contains('| sometimes-broken | error |'));
    });

    test('an empty report renders without a table', () {
      const report = EvalReport(results: []);
      final markdown = report.toMarkdown();
      expect(markdown, contains('- cases: 0'));
      expect(markdown, contains('- pass rate: 100.0% (0/0)'));
      expect(markdown, isNot(contains('| case |')));
      expect(report.passRate, 1.0);
      expect(report.flakinessRate, 0.0);
      expect(report.errorCount, 0);
    });

    test('errorCount counts cases with errors, not plain fails', () {
      expect(mixedReport().errorCount, 1);
      expect(flakyReport().errorCount, 0);
    });
  });

  group('EvalReport.toJson', () {
    test('encodes the full result tree', () {
      expect(mixedReport().toJson(), {
        'modelId': 'fake-1',
        'repeat': 1,
        'caseCount': 3,
        'passedCount': 1,
        'passRate': 0.3333,
        'flakyCount': 0,
        'flakinessRate': 0.0,
        'cases': [
          {
            'id': 'greeting',
            'passed': true,
            'flaky': false,
            'hasError': false,
            'attempts': [
              {
                'output': 'Hello there!',
                'passed': true,
                'latencyMs': 12,
                'fromCache': false,
                'modelError': null,
                'checks': [
                  {
                    'description': 'contains "hello"',
                    'passed': true,
                    'score': null,
                    'detail': '',
                    'error': null,
                  },
                  {
                    'description': 'does not contain "bye"',
                    'passed': true,
                    'score': null,
                    'detail': '',
                    'error': null,
                  },
                ],
              },
            ],
          },
          {
            'id': 'json',
            'passed': false,
            'flaky': false,
            'hasError': false,
            'attempts': [
              {
                'output': 'not json',
                'passed': false,
                'latencyMs': 30,
                'fromCache': true,
                'modelError': null,
                'checks': [
                  {
                    'description': 'is valid JSON',
                    'passed': false,
                    'score': null,
                    'detail': 'not valid JSON: Unexpected character',
                    'error': null,
                  },
                ],
              },
            ],
          },
          {
            'id': 'broken',
            'passed': false,
            'flaky': false,
            'hasError': true,
            'attempts': [
              {
                'output': '',
                'passed': false,
                'latencyMs': 5,
                'fromCache': false,
                'modelError': 'Exception: boom',
                'checks': <Object?>[],
              },
            ],
          },
        ],
      });
    });

    test('encodes to a stable JSON string (golden)', () {
      const expected =
          '{"modelId":null,"repeat":2,"caseCount":1,"passedCount":0,'
          '"passRate":0.0,"flakyCount":1,"flakinessRate":1.0,'
          '"cases":[{"id":"flaky-case","passed":false,"flaky":true,'
          '"hasError":false,'
          '"attempts":[{"output":"yes","passed":true,"latencyMs":10,'
          '"fromCache":false,"modelError":null,'
          '"checks":[{"description":"contains \\"yes\\"","passed":true,'
          '"score":null,"detail":"","error":null}]},'
          '{"output":"no","passed":false,"latencyMs":11,'
          '"fromCache":false,"modelError":null,'
          '"checks":[{"description":"contains \\"yes\\"","passed":false,'
          '"score":null,"detail":"output does not contain \\"yes\\"",'
          '"error":null}]}]}]}';
      expect(jsonEncode(flakyReport().toJson()), expected);
    });

    test('judge scores appear in the JSON output', () {
      const report = EvalReport(
        results: [
          CaseResult(
            caseId: 'judged',
            attempts: [
              AttemptResult(
                output: 'answer',
                checks: [
                  CheckOutcome(
                    description: 'judge score >= 0.7',
                    result: CheckResult.pass(score: 0.85, detail: 'good'),
                  ),
                ],
                latency: Duration(milliseconds: 40),
                fromCache: false,
              ),
            ],
          ),
        ],
      );
      final json = report.toJson();
      final cases = json['cases'] as List<Object?>;
      final firstCase = cases.first as Map<String, Object?>;
      final attempts = firstCase['attempts'] as List<Object?>;
      final attempt = attempts.first as Map<String, Object?>;
      final checks = attempt['checks'] as List<Object?>;
      final check = checks.first as Map<String, Object?>;
      expect(check['score'], 0.85);
    });
  });
}
