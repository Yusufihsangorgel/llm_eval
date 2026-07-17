/// The outcome of a single check applied to a model output.
///
/// A result is exactly one of three things:
///
/// * a pass ([passed] is true, [error] is null),
/// * a fail ([passed] is false, [error] is null),
/// * an error ([passed] is false, [error] holds a message).
///
/// Fails and errors are kept apart on purpose. A fail means the check ran
/// and the output did not satisfy it. An error means the check could not
/// produce a verdict at all, for example when a judge response cannot be
/// parsed. Reports show the two differently so a broken harness is not
/// mistaken for a failing model.
class CheckResult {
  /// Creates a passing result.
  const CheckResult.pass({this.score, this.detail = ''})
    : passed = true,
      error = null;

  /// Creates a failing result.
  const CheckResult.fail({this.score, this.detail = ''})
    : passed = false,
      error = null;

  /// Creates an error result carrying [message].
  const CheckResult.error(String message)
    : passed = false,
      score = null,
      detail = '',
      error = message;

  /// Whether the output satisfied the check.
  ///
  /// Always false for error results; use [isError] to tell an error apart
  /// from a plain fail.
  final bool passed;

  /// An optional score between 0.0 and 1.0.
  ///
  /// Set by judge checks; null for checks that only produce a verdict.
  final double? score;

  /// A short human-readable explanation of the verdict.
  final String detail;

  /// The message describing why no verdict could be produced, or null
  /// when the check ran normally.
  final String? error;

  /// Whether this result is an error rather than a verdict.
  bool get isError => error != null;
}
