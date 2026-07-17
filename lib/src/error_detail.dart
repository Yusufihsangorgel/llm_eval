/// Formats [error] as `context: error`, followed by the first three
/// frames of [stackTrace] collapsed onto one line.
///
/// Error strings travel through reports (Markdown lists, JSON values), so
/// the result deliberately stays on a single line.
String describeError(String context, Object error, StackTrace stackTrace) {
  final frames = stackTrace
      .toString()
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .take(3)
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .join(' | ');
  if (frames.isEmpty) return '$context: $error';
  return '$context: $error (stack: $frames)';
}
