import 'model_call.dart';

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

/// Caching for nested [ModelCall]s that `EvalSuite.run` never sees.
extension NestedModelCallCaching on ResponseCache {
  /// Wraps [call] so its responses are served from and stored in this
  /// cache under [modelId].
  ///
  /// `EvalSuite.run` caches the model under test, but a nested call such
  /// as the judge in a `Check.judge` runs inside a check and never touches
  /// that cache. Without this wrapper a warm cache skips the model under
  /// test yet still calls the judge on every run, so the suite is neither
  /// deterministic nor free. Wrap the judge to give it a cache path:
  ///
  /// ```dart
  /// Check.judge(
  ///   judge: cache.wrap(judgeModel, modelId: 'judge-v1'),
  ///   rubric: '...',
  /// )
  /// ```
  ///
  /// The key uses the same length-prefixed `modelId` and prompt scheme
  /// `EvalSuite.run` uses, so a wrapped judge lives alongside the model
  /// entries in the same cache without colliding. Give each judge its own
  /// [modelId] so pinning or changing one judge re-records only its own
  /// responses.
  ///
  /// A read that throws is treated as a miss and falls through to [call],
  /// matching how `EvalSuite.run` tolerates a broken cache. A write that
  /// throws propagates, so a judge check surfaces it as an error result
  /// instead of silently returning a response the cache never stored.
  ModelCall wrap(ModelCall call, {required String modelId}) {
    return (String prompt) async {
      // Same length-prefixed key as EvalSuite._runAttempt; keep in sync.
      final key = '${modelId.length}:$modelId\n$prompt';
      String? cached;
      try {
        cached = await read(key);
      } catch (_) {
        cached = null;
      }
      if (cached != null) return cached;
      final response = await call(prompt);
      await write(key, response);
      return response;
    };
  }
}
