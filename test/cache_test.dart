import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llm_eval/io.dart';
import 'package:llm_eval/llm_eval.dart';
import 'package:test/test.dart';

/// A map-backed [ResponseCache] for tests.
class MemoryCache implements ResponseCache {
  final Map<String, String> entries = {};

  @override
  Future<String?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, String response) async {
    entries[key] = response;
  }
}

/// A cache whose reads always throw.
class BrokenReadCache implements ResponseCache {
  int writes = 0;

  @override
  Future<String?> read(String key) async =>
      throw const FileSystemException('read failed');

  @override
  Future<void> write(String key, String response) async {
    writes++;
  }
}

/// A cache whose writes always throw.
class BrokenWriteCache implements ResponseCache {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String response) async =>
      throw const FileSystemException('disk full');
}

void main() {
  group('FileResponseCache', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('llm_eval_cache_test');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('a second run never calls the model', () async {
      var calls = 0;
      Future<String> model(String prompt) async {
        calls++;
        return 'response to $prompt';
      }

      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'p1', checks: [Check.contains('response')]),
        EvalCase(id: 'b', prompt: 'p2', checks: [Check.contains('response')]),
      ]);

      final cache = FileResponseCache(tempDir.path);
      final first = await suite.run(model, cache: cache, modelId: 'm1');
      expect(calls, 2);
      expect(first.results.every((r) => r.attempts.single.fromCache), isFalse);

      calls = 0;
      final second = await suite.run(model, cache: cache, modelId: 'm1');
      expect(calls, 0, reason: 'a warm cache must serve every response');
      expect(second.results.every((r) => r.attempts.single.fromCache), isTrue);
      for (var i = 0; i < first.results.length; i++) {
        expect(
          second.results[i].attempts.single.output,
          first.results[i].attempts.single.output,
        );
      }
    });

    test('stores responses under the sha256 of modelId and prompt', () async {
      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'p1', checks: [Check.contains('response')]),
      ]);
      await suite.run(
        (prompt) async => 'response to $prompt',
        cache: FileResponseCache(tempDir.path),
        modelId: 'm1',
      );

      final digest = sha256.convert(utf8.encode('2:m1\np1')).toString();
      final file = File('${tempDir.path}/$digest.txt');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), 'response to p1');
    });

    test('leaves no temporary files behind', () async {
      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'p1', checks: [Check.contains('response')]),
        EvalCase(id: 'b', prompt: 'p2', checks: [Check.contains('response')]),
      ]);
      await suite.run(
        (prompt) async => 'response to $prompt',
        cache: FileResponseCache(tempDir.path),
        modelId: 'm1',
      );

      final leftovers = tempDir
          .listSync()
          .where((entity) => entity.path.contains('.tmp.'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('a different modelId misses the cache', () async {
      var calls = 0;
      Future<String> model(String prompt) async {
        calls++;
        return 'ok';
      }

      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'p1', checks: [Check.contains('ok')]),
      ]);
      final cache = FileResponseCache(tempDir.path);
      await suite.run(model, cache: cache, modelId: 'm1');
      await suite.run(model, cache: cache, modelId: 'm2');
      expect(calls, 2, reason: 'each modelId gets its own cache entry');
    });

    test('read returns null on a cold cache', () async {
      final cache = FileResponseCache('${tempDir.path}/never-created');
      expect(await cache.read('anything'), isNull);
    });
  });

  group('custom ResponseCache', () {
    test('the suite works against any ResponseCache implementation', () async {
      var calls = 0;
      Future<String> model(String prompt) async {
        calls++;
        return 'ok';
      }

      final cache = MemoryCache();
      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'p1', checks: [Check.contains('ok')]),
      ]);

      await suite.run(model, cache: cache, modelId: 'm1');
      expect(calls, 1);
      expect(cache.entries, hasLength(1));

      final report = await suite.run(model, cache: cache, modelId: 'm1');
      expect(calls, 1);
      expect(report.results.single.attempts.single.fromCache, isTrue);
    });

    test('rejects repeat > 1 combined with a cache', () async {
      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'p1', checks: [Check.contains('ok')]),
      ]);
      expect(
        () =>
            suite.run((prompt) async => 'ok', cache: MemoryCache(), repeat: 3),
        throwsArgumentError,
      );
    });

    test('the model label and the prompt cannot collide in the key', () async {
      var calls = 0;
      Future<String> model(String prompt) async {
        calls++;
        return 'ok';
      }

      final cache = MemoryCache();
      await EvalSuite([
        EvalCase(id: 'a', prompt: 'foo\nbar', checks: [Check.contains('ok')]),
      ]).run(model, cache: cache, modelId: 'm1');
      await EvalSuite([
        EvalCase(id: 'b', prompt: 'bar', checks: [Check.contains('ok')]),
      ]).run(model, cache: cache, modelId: 'm1\nfoo');

      expect(calls, 2, reason: 'the two label and prompt pairs are distinct');
      expect(cache.entries, hasLength(2));
    });

    test('a throwing cache read is treated as a miss', () async {
      var calls = 0;
      Future<String> model(String prompt) async {
        calls++;
        return 'ok';
      }

      final cache = BrokenReadCache();
      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'p1', checks: [Check.contains('ok')]),
        EvalCase(id: 'b', prompt: 'p2', checks: [Check.contains('ok')]),
      ]);
      final report = await suite.run(model, cache: cache);

      expect(calls, 2, reason: 'every read failure falls back to the model');
      expect(cache.writes, 2);
      expect(report.passRate, 1.0);
      expect(report.errorCount, 0);
      for (final result in report.results) {
        expect(result.attempts.single.fromCache, isFalse);
      }
    });

    test('a throwing cache write errors the attempt, not the run', () async {
      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'p1', checks: [Check.contains('ok')]),
        EvalCase(id: 'b', prompt: 'p2', checks: [Check.contains('ok')]),
      ]);
      final report = await suite.run(
        (prompt) async => 'ok $prompt',
        cache: BrokenWriteCache(),
      );

      expect(report.results, hasLength(2));
      expect(report.errorCount, 2);
      for (final result in report.results) {
        final attempt = result.attempts.single;
        expect(attempt.modelError, contains('cache write failed'));
        expect(attempt.modelError, contains('disk full'));
        expect(attempt.output, startsWith('ok'), reason: 'output is kept');
        expect(attempt.checks, isEmpty, reason: 'error attempts skip checks');
        expect(attempt.passed, isFalse);
      }
    });
  });

  group('ResponseCache.wrap', () {
    test('a warm cache does not re-invoke a wrapped judge', () async {
      var judgeCalls = 0;
      Future<String> judge(String prompt) async {
        judgeCalls++;
        return 'SCORE: 1.0';
      }

      final cache = MemoryCache();
      final suite = EvalSuite([
        EvalCase(
          id: 'a',
          prompt: 'p1',
          checks: [
            Check.judge(
              judge: cache.wrap(judge, modelId: 'judge-v1'),
              rubric: 'anything',
            ),
          ],
        ),
      ]);

      final first = await suite.run(
        (prompt) async => 'model output',
        cache: cache,
        modelId: 'm1',
      );
      expect(judgeCalls, 1);
      expect(first.passRate, 1.0);
      expect(first.results.single.attempts.single.fromCache, isFalse);

      judgeCalls = 0;
      final second = await suite.run(
        (prompt) async => 'model output',
        cache: cache,
        modelId: 'm1',
      );
      expect(
        judgeCalls,
        0,
        reason: 'a warm cache must not call the wrapped judge again',
      );
      expect(second.passRate, 1.0);
      expect(second.results.single.attempts.single.fromCache, isTrue);
    });

    test('an unwrapped judge still fires on a warm cache', () async {
      // Documents the gap wrap closes: the suite caches the model under
      // test but not a nested judge, so a raw judge runs every time.
      var judgeCalls = 0;
      Future<String> judge(String prompt) async {
        judgeCalls++;
        return 'SCORE: 1.0';
      }

      final cache = MemoryCache();
      final suite = EvalSuite([
        EvalCase(
          id: 'a',
          prompt: 'p1',
          checks: [Check.judge(judge: judge, rubric: 'anything')],
        ),
      ]);

      await suite.run(
        (prompt) async => 'model output',
        cache: cache,
        modelId: 'm1',
      );
      final second = await suite.run(
        (prompt) async => 'model output',
        cache: cache,
        modelId: 'm1',
      );
      expect(second.results.single.attempts.single.fromCache, isTrue);
      expect(judgeCalls, 2, reason: 'the raw judge is not cached');
    });

    test('wrap keys match the scheme the suite uses', () async {
      final cache = MemoryCache();
      final judge = cache.wrap((prompt) async => 'SCORE: 1.0', modelId: 'j1');
      await judge('hello');
      expect(cache.entries.keys.single, '2:j1\nhello');
    });

    test('a wrapped call falls through to the model on a read failure',
        () async {
      var calls = 0;
      final cache = BrokenReadCache();
      final call = cache.wrap((prompt) async {
        calls++;
        return 'graded';
      }, modelId: 'j1');
      expect(await call('x'), 'graded');
      expect(calls, 1, reason: 'a broken read is treated as a miss');
      expect(cache.writes, 1);
    });
  });
}
