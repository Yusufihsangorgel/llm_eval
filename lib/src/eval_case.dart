import 'check.dart';

/// A single prompt together with the checks its output must satisfy.
class EvalCase {
  /// Creates a case.
  EvalCase({
    required this.id,
    required this.prompt,
    required this.checks,
    this.metadata = const {},
  });

  /// Identifier used in reports. Keep it unique within a suite.
  final String id;

  /// The prompt sent to the model under test.
  final String prompt;

  /// The checks applied to the model output, evaluated in order.
  final List<Check> checks;

  /// Free-form data for the caller's own bookkeeping.
  ///
  /// The harness does not interpret or report it.
  final Map<String, Object?> metadata;
}
