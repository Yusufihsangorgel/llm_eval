import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'response_cache.dart';

/// A [ResponseCache] that stores each response as a file in a directory.
///
/// File names are the SHA-256 hex digest of the key, so keys of any
/// length and content are safe. The directory is created on first write.
/// Commit the directory to version control, or restore it from a CI
/// cache, to rerun a suite without calling the model.
///
/// Writes are atomic: each response goes to a temporary file first and is
/// then moved into place with a rename, so a concurrent reader (including
/// one in another process) never observes a partially written response.
class FileResponseCache implements ResponseCache {
  /// Creates a cache rooted at [directory].
  FileResponseCache(String directory) : _directory = Directory(directory);

  final Directory _directory;

  static int _tempCounter = 0;

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
    final target = _fileFor(key);
    final temp = File('${target.path}.tmp.$pid.${_tempCounter++}');
    await temp.writeAsString(response, flush: true);
    await temp.rename(target.path);
  }
}
