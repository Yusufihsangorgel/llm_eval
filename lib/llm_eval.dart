/// A test harness for LLM outputs.
///
/// Define [EvalCase]s (a prompt plus a list of [Check]s), run them with
/// [EvalSuite] against any model reachable through a [ModelCall], and
/// consume the resulting [EvalReport] as Markdown or JSON. A
/// [FileResponseCache] makes reruns deterministic in CI.
library;

export 'src/check.dart';
export 'src/check_result.dart';
export 'src/eval_case.dart';
export 'src/eval_report.dart';
export 'src/eval_suite.dart';
export 'src/model_call.dart';
export 'src/response_cache.dart';
