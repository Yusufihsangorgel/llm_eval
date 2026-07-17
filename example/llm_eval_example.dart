import 'package:llm_eval/llm_eval.dart';

/// A stand-in model with canned answers.
///
/// In a real project, bind [ModelCall] to your model client instead: an
/// OpenAI or Anthropic SDK call, an Ollama HTTP request, or anything
/// else that turns a prompt into a string.
Future<String> fakeModel(String prompt) async {
  if (prompt.contains('capital of France')) {
    return 'The capital of France is Paris.';
  }
  if (prompt.contains('JSON')) {
    return '{"name": "llm_eval", "language": "Dart"}';
  }
  return 'I do not know.';
}

Future<void> main() async {
  final suite = EvalSuite([
    EvalCase(
      id: 'capital-question',
      prompt: 'What is the capital of France?',
      checks: [Check.contains('paris'), Check.notContains('berlin')],
    ),
    EvalCase(
      id: 'structured-output',
      prompt: 'Describe this package as JSON with a "name" field.',
      checks: [
        Check.isValidJson(
          where: (decoded) => decoded is Map && decoded['name'] == 'llm_eval',
        ),
      ],
    ),
    EvalCase(
      id: 'unknown-question',
      prompt: 'What is the airspeed velocity of an unladen swallow?',
      checks: [
        Check.predicate('admits uncertainty', (o) => o.contains('do not know')),
      ],
    ),
  ]);

  final report = await suite.run(fakeModel, modelId: 'fake-model');
  print(report.toMarkdown());
}
