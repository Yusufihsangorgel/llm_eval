/// Stores model responses between runs.
///
/// `EvalSuite.run` builds a cache key from its `modelId` argument and the
/// case prompt, reads the cache before calling the model, and writes the
/// response back after a miss. With a warm cache a rerun never calls the
/// model, which makes eval runs in CI deterministic and free.
///
/// A file-backed implementation, `FileResponseCache`, lives in
/// `package:llm_eval/io.dart` so that this core library stays free of
/// `dart:io` and usable on every platform, including the web.
abstract interface class ResponseCache {
  /// Returns the cached response for [key], or null on a miss.
  Future<String?> read(String key);

  /// Stores [response] under [key].
  Future<void> write(String key, String response);
}
