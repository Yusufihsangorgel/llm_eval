/// File-backed response caching, for platforms with `dart:io`.
///
/// This library is separate from the core so that `package:llm_eval`
/// itself stays platform-neutral and runs on the web. Import it where a
/// file cache is wanted:
///
/// ```dart
/// import 'package:llm_eval/llm_eval.dart';
/// import 'package:llm_eval/io.dart' show FileResponseCache;
/// ```
library;

export 'src/file_response_cache.dart';
