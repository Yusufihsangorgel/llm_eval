/// Formats [error] as `context: error`, followed by the first three
/// frames of [stackTrace] collapsed onto one line.
///
/// Error strings travel through reports (Markdown lists, JSON values), so
/// the result deliberately stays on a single line.
///
/// Frames pointing at files outside a package are shortened to the last two
/// path segments. A `file:///` frame carries the absolute layout of whatever
/// machine ran the suite, and these reports are written to be pasted into pull
/// requests and job summaries: on a developer's laptop that is a home
/// directory, and on a runner it is a checkout path nobody reading the report
/// can use. The file and line are what identify the frame, and those are kept.
String describeError(String context, Object error, StackTrace stackTrace) {
  final frames = stackTrace
      .toString()
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .take(3)
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .map(_shortenFileUris)
      .join(' | ');
  if (frames.isEmpty) return '$context: $error';
  return '$context: $error (stack: $frames)';
}

/// `file:///a/b/c/pkg/lib/x.dart` becomes `lib/x.dart`, leaving `package:` and
/// `dart:` frames alone since those are already relative to something shared.
String _shortenFileUris(String frame) =>
    frame.replaceAllMapped(RegExp(r'file://(/[^\s():]*)'), (m) {
      final segments = m
          .group(1)!
          .split('/')
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      if (segments.length <= 2) return segments.join('/');
      return segments.sublist(segments.length - 2).join('/');
    });
