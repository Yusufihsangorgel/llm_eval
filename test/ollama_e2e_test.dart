import 'dart:convert';
import 'dart:io';

import 'package:llm_eval/llm_eval.dart';
import 'package:test/test.dart';

const _host = 'localhost';
const _port = 11434;
const _model = 'llama3.2:3b';

/// Returns true when a local Ollama server is reachable and has [_model].
Future<bool> _ollamaAvailable() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(Uri.http('$_host:$_port', '/api/tags'));
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != 200) return false;
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return false;
    final models = decoded['models'];
    if (models is! List<dynamic>) return false;
    return models.any((m) => m is Map<String, dynamic> && m['name'] == _model);
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// A [ModelCall] backed by the Ollama generate endpoint.
Future<String> _ollamaGenerate(String prompt) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.http('$_host:$_port', '/api/generate'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'model': _model,
        'prompt': prompt,
        'stream': false,
        'options': {'temperature': 0},
      }),
    );
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != 200) {
      throw HttpException('Ollama returned ${response.statusCode}: $body');
    }
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return decoded['response'] as String;
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('runs a real eval against a local Ollama model', () async {
    if (!await _ollamaAvailable()) {
      markTestSkipped(
        'Ollama with model $_model is not reachable at '
        'http://$_host:$_port; skipping the end-to-end test.',
      );
      return;
    }

    final suite = EvalSuite([
      EvalCase(
        id: 'echo-pong',
        prompt: 'Reply with exactly one word: pong',
        checks: [Check.contains('pong')],
      ),
      EvalCase(
        id: 'json-object',
        prompt:
            'Return only a JSON object with a single key "ok" whose '
            'value is true. No prose, no code fences.',
        checks: [Check.isValidJson()],
      ),
    ]);

    final report = await suite.run(
      _ollamaGenerate,
      concurrency: 1,
      modelId: _model,
    );

    // The point of this test is that the harness works end to end against
    // a real model. Model behavior itself is not asserted: a small local
    // model may legitimately fail a check.
    expect(report.results, hasLength(2));
    for (final result in report.results) {
      final attempt = result.attempts.single;
      expect(attempt.modelError, isNull);
      expect(attempt.output, isNotEmpty);
      expect(attempt.fromCache, isFalse);
    }
    print(report.toMarkdown());
  }, tags: ['e2e']);
}
