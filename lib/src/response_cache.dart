import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Stores model responses between runs.
///
/// `EvalSuite.run` builds a cache key from its `modelId` argument and the
/// case prompt, reads the cache before calling the model, and writes the
/// response back after a miss. With a warm cache a rerun never calls the
/// model, which makes eval runs in CI deterministic and free.
abstract interface class ResponseCache {
  /// Returns the cached response for [key], or null on a miss.
  Future<String?> read(String key);

  /// Stores [response] under [key].
  Future<void> write(String key, String response);
}

/// A [ResponseCache] that stores each response as a file in a directory.
///
/// File names are the SHA-256 hex digest of the key, so keys of any
/// length and content are safe. The directory is created on first write.
/// Commit the directory to version control, or restore it from a CI
/// cache, to rerun a suite without calling the model.
class FileResponseCache implements ResponseCache {
  /// Creates a cache rooted at [directory].
  FileResponseCache(String directory) : _directory = Directory(directory);

  final Directory _directory;

  File _fileFor(String key) {
    final digest = sha256.convert(utf8.encode(key)).toString();
    return File('${_directory.path}/$digest.txt');
  }

  @override
  Future<String?> read(String key) async {
    final file = _fileFor(key);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String key, String response) async {
    await _directory.create(recursive: true);
    await _fileFor(key).writeAsString(response);
  }
}
