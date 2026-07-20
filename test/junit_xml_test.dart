import 'package:llm_eval/llm_eval.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

CheckOutcome _pass(String description) => CheckOutcome(
      description: description,
      result: const CheckResult.pass(detail: 'ok'),
    );

CheckOutcome _fail(String description, String detail) => CheckOutcome(
      description: description,
      result: CheckResult.fail(detail: detail),
    );

CheckOutcome _errored(String description, String error) => CheckOutcome(
      description: description,
      result: CheckResult.error(error),
    );

AttemptResult _attempt({
  String output = 'out',
  List<CheckOutcome> checks = const [],
  String? modelError,
  int ms = 10,
}) =>
    AttemptResult(
      output: output,
      checks: checks,
      latency: Duration(milliseconds: ms),
      fromCache: false,
      modelError: modelError,
    );

void main() {
  test('a passing report parses and every case is a bare testcase', () {
    final report = EvalReport(
      modelId: 'gpt-test',
      results: [
        CaseResult(
          caseId: 'greeting',
          attempts: [
            _attempt(checks: [_pass('says hello')], ms: 120),
          ],
        ),
        CaseResult(
          caseId: 'json',
          attempts: [
            _attempt(checks: [_pass('is json')], ms: 80),
          ],
        ),
      ],
    );

    final document = XmlDocument.parse(report.toJUnitXml());
    final suites = document.rootElement;
    expect(suites.name.local, 'testsuites');
    expect(suites.getAttribute('tests'), '2');
    expect(suites.getAttribute('failures'), '0');
    expect(suites.getAttribute('errors'), '0');
    // 120ms + 80ms.
    expect(suites.getAttribute('time'), '0.200');

    final cases = document.findAllElements('testcase').toList();
    expect(cases.map((c) => c.getAttribute('name')), ['greeting', 'json']);
    expect(cases.every((c) => c.childElements.isEmpty), isTrue);
    expect(cases.first.getAttribute('classname'), 'gpt-test');
  });

  test('a failing case becomes a failure with the checks that failed', () {
    final report = EvalReport(
      results: [
        CaseResult(
          caseId: 'capital',
          attempts: [
            _attempt(
              output: 'Berlin',
              checks: [
                _pass('is a city'),
                _fail('contains paris', 'output did not contain "paris"'),
              ],
            ),
          ],
        ),
      ],
    );

    final document = XmlDocument.parse(report.toJUnitXml());
    expect(document.rootElement.getAttribute('failures'), '1');
    expect(document.rootElement.getAttribute('errors'), '0');

    final failure = document.findAllElements('failure').single;
    expect(failure.getAttribute('message'), contains('contains paris'));
    expect(failure.innerText, contains('output did not contain'));
    // The model output is in the body, which is the point of reading it in CI.
    expect(failure.innerText, contains('Berlin'));
  });

  test('a model error becomes an error, not a failure', () {
    final report = EvalReport(
      results: [
        CaseResult(
          caseId: 'timeout',
          attempts: [_attempt(output: '', modelError: 'connection closed')],
        ),
      ],
    );

    final document = XmlDocument.parse(report.toJUnitXml());
    expect(document.rootElement.getAttribute('errors'), '1');
    expect(document.rootElement.getAttribute('failures'), '0');
    final error = document.findAllElements('error').single;
    expect(error.getAttribute('message'), contains('connection closed'));
    expect(document.findAllElements('failure'), isEmpty);
  });

  test('an errored check is an error too', () {
    final report = EvalReport(
      results: [
        CaseResult(
          caseId: 'predicate',
          attempts: [
            _attempt(checks: [_errored('custom check', 'threw StateError')]),
          ],
        ),
      ],
    );
    final document = XmlDocument.parse(report.toJUnitXml());
    expect(document.findAllElements('error').single.getAttribute('message'),
        contains('threw StateError'));
  });

  test('a flaky case fails and says how many attempts passed', () {
    final report = EvalReport(
      repeat: 3,
      results: [
        CaseResult(
          caseId: 'sometimes',
          attempts: [
            _attempt(checks: [_pass('ok')]),
            _attempt(checks: [_fail('ok', 'missed')]),
            _attempt(checks: [_pass('ok')]),
          ],
        ),
      ],
    );
    final document = XmlDocument.parse(report.toJUnitXml());
    final failure = document.findAllElements('failure').single;
    expect(failure.getAttribute('message'), contains('flaky'));
    expect(failure.getAttribute('message'), contains('2 of 3'));
    // Each attempt is labelled in the body so you can see which one drifted.
    expect(failure.innerText, contains('attempt 2:'));
  });

  test('hostile model output still produces a parseable document', () {
    // Everything a model can emit that would break naive string building:
    // markup, entities, quotes, and a control byte XML 1.0 forbids outright.
    const nasty = 'a < b & c > d "quoted" \'single\' </failure> ';
    final report = EvalReport(
      modelId: 'model & "co" <v1>',
      results: [
        CaseResult(
          caseId: 'case <1> & "two"',
          attempts: [
            _attempt(
              output: nasty,
              checks: [_fail('no markup $nasty', 'saw $nasty')],
            ),
          ],
        ),
      ],
    );

    // The assertion is simply that this parses; a stray < or control byte
    // would make a CI system reject the entire report.
    final document = XmlDocument.parse(report.toJUnitXml());
    final testcase = document.findAllElements('testcase').single;
    expect(testcase.getAttribute('name'), 'case <1> & "two"');
    expect(testcase.getAttribute('classname'), 'model & "co" <v1>');
    final failure = document.findAllElements('failure').single;
    // The text survives round-trip, minus the characters XML cannot carry.
    expect(failure.innerText, contains('a < b & c > d "quoted"'));
    expect(failure.innerText, contains('</failure>'));
    expect(failure.innerText, isNot(contains('')));
  });

  test('an empty report is still a valid document', () {
    const report = EvalReport(results: []);
    final document = XmlDocument.parse(report.toJUnitXml());
    expect(document.rootElement.getAttribute('tests'), '0');
    expect(document.findAllElements('testcase'), isEmpty);
  });

  test('without a modelId the suite falls back to the package name', () {
    final report = EvalReport(
      results: [
        CaseResult(caseId: 'a', attempts: [_attempt(checks: [_pass('ok')])]),
      ],
    );
    final document = XmlDocument.parse(report.toJUnitXml());
    expect(document.findAllElements('testsuite').single.getAttribute('name'),
        'llm_eval');
  });
}
