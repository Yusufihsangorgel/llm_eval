import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

      final digest = sha256.convert(utf8.encode('m1\np1')).toString();
      final file = File('${tempDir.path}/$digest.txt');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), 'response to p1');
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

    test('with repeat, only the first attempt calls the model', () async {
      var calls = 0;
      Future<String> model(String prompt) async {
        calls++;
        return 'ok';
      }

      final suite = EvalSuite([
        EvalCase(id: 'a', prompt: 'p1', checks: [Check.contains('ok')]),
      ]);
      final report = await suite.run(model, cache: MemoryCache(), repeat: 3);

      expect(calls, 1);
      final attempts = report.results.single.attempts;
      expect(attempts, hasLength(3));
      expect(attempts[0].fromCache, isFalse);
      expect(attempts[1].fromCache, isTrue);
      expect(attempts[2].fromCache, isTrue);
    });
  });
}
