/// A test harness for LLM outputs.
///
/// Define [EvalCase]s (a prompt plus a list of [Check]s), run them with
/// [EvalSuite] against any model reachable through a [ModelCall], and
/// consume the resulting [EvalReport] as Markdown or JSON.
///
/// This library is pure Dart and runs on every platform. The file-backed
/// response cache, `FileResponseCache`, needs `dart:io` and lives in
/// `package:llm_eval/io.dart`.
library;

export 'src/check.dart' show Check;
export 'src/check_result.dart' show CheckResult;
export 'src/eval_case.dart' show EvalCase;
export 'src/eval_report.dart'
    show AttemptResult, CaseResult, CheckOutcome, EvalReport;
export 'src/eval_suite.dart' show EvalSuite;
export 'src/model_call.dart' show ModelCall;
export 'src/response_cache.dart' show NestedModelCallCaching, ResponseCache;
