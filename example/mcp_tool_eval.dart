// The bridge between this package and mcp_probe.
//
// An MCP server's tools return text that a model consumes. Whether that
// text is any good is an evaluation question — this package. Whether the
// server behaves is a conformance question — mcp_probe. This file is the
// two together, which is the honest use case for both and which nobody
// had written down.
//
//   dart run example/mcp_tool_eval.dart
//
// No live model, no network. The replies are a recorded session against
// mcp_probe's well-behaved fixture (`test/fixtures/well_behaved_server.dart`
// in that repo): echo, read_env, fail_tool, the greeting resource, the
// greet prompt. The fixture is deterministic, so the recording is just
// what the source returns.
//
// ---------------------------------------------------------------------------
// Dependency
//
// mcp_probe is not a dependency of this package, not even a dev one.
//
// A path dep (`../mcp_probe`) would make `dart pub publish` refuse the
// package and would make this repo's CI fail `dart pub get` — the runner
// checks out llm_eval alone. A hosted or git dep would pull dart_mcp,
// matcher and json_rpc_2 into a lockfile whose runtime side is `crypto`,
// and the examples here are otherwise all fakes (see AGENTS.md). The
// fixture also lives under mcp_probe's `test/fixtures/`, which is not an
// import: you start it as a command, and that command is not on the path
// of anyone who added `llm_eval`.
//
// In a project that owns an MCP server, mcp_probe belongs in *that*
// project's `dev_dependencies`, next to this package. The live shape is
// at the bottom of this comment. This file is the same eval without
// coupling the two pubspecs.
//
// ---------------------------------------------------------------------------
// The seam
//
// The two APIs do not fit together. Wrapping until they look like one
// call would hide the part worth reading.
//
// 1. `ModelCall` is `Future<String> Function(String prompt)`.
//    `McpServerHarness.callTool` is
//    `Future<CallToolResult> Function(String name, {arguments})`.
//    There is no shared type for "a tool invocation". `EvalCase.prompt`
//    is a string the suite sends to the model; a tool call is a name and
//    a map. The prompts in this file are labels that the lookup uses as
//    keys, not text a model would see. That is a stretch, and it is
//    yours to keep making in a live binding.
//
// 2. Checks run on a `String`. A tool result is `List<Content>` (text,
//    image, resource, …) plus `bool? isError`. Flattening is yours.
//    Images vanish unless you decide otherwise. `isError` is nullable;
//    do not write `if (result.isError)` — null means success
//    (`mcp_probe` AGENTS.md, callTool).
//
// 3. In-band failure is not a throw. mcp_probe: `isError == true` is a
//    tool that ran and reported failure; a protocol reject throws
//    `RpcException` from `package:json_rpc_2`. llm_eval: a throw is
//    `AttemptResult.modelError` (error, not fail) and a string is
//    checked. Flatten `fail_tool` to "intentional failure" and
//    `Check.contains('intentional')` passes — the tool failed, the eval
//    is green. Throw on `isError` and it lands in `errorCount`, which is
//    the mapping that keeps a dead tool out of the pass rate. Neither
//    package picks for you. The two one-case runs at the bottom show
//    both.
//
// 4. Resources and prompts are further types (`ReadResourceResult`,
//    `GetPromptResult`), not `CallToolResult`. Same flattening problem,
//    different fields. mcp_probe does not re-export the dart_mcp types;
//    a live file imports `package:dart_mcp/client.dart` for
//    `TextContent`.
//
// 5. `checkServer` returns a `ConformanceReport`. `EvalSuite.run`
//    returns an `EvalReport`. They do not compose. Run both; do not
//    fold a handshake failure into a pass rate.
//
// 6. The cache key is `modelId` plus the prompt. Tool arguments are not
//    in it unless you put them in the prompt string. Change the server,
//    leave the prompt alone: `fromCache: true`, the new tool is never
//    called. Same trap as a stale model cache; bump `modelId`.
//
// ---------------------------------------------------------------------------
// Live wiring, in a project that has both packages
//
//   import 'package:dart_mcp/client.dart';
//   import 'package:llm_eval/llm_eval.dart';
//   import 'package:mcp_probe/mcp_probe.dart';
//
//   final harness = await McpServerHarness.start(
//     'dart',
//     args: ['run', 'path/to/server.dart'],
//   );
//   try {
//     final result = await harness.callTool(
//       'echo',
//       arguments: {'text': 'The capital of France is Paris.'},
//     );
//     if (result.isError ?? false) {
//       throw StateError('tool echo isError'); // or flatten; see (3)
//     }
//     final text = [
//       for (final c in result.content)
//         if (c.isText) (c as TextContent).text,
//     ].join('\n');
//     // `text` is what you hand this package: a ModelCall that returns
//     // it, or the output a real model produced after reading it.
//   } finally {
//     await harness.shutdown();
//   }
//
//   final conformance = await checkServer(
//     'dart',
//     args: ['run', 'path/to/server.dart'],
//   );
//   // Gate on conformance.hasErrors separately from report.passRate.
//
import 'dart:io';

import 'package:llm_eval/llm_eval.dart';

/// One recorded MCP turn: the method, the text the fixture returned, and
/// whether it set `isError`.
///
/// This is the slice of `CallToolResult` / `ReadResourceResult` /
/// `GetPromptResult` that an eval can see once you have flattened it. The
/// live types live in `package:dart_mcp/client.dart`; mcp_probe does not
/// re-export them.
final class RecordedTurn {
  const RecordedTurn({
    required this.method,
    required this.text,
    this.isError = false,
  });

  /// MCP method plus arguments, used as the `EvalCase.prompt` lookup key.
  final String method;

  /// Joined text content. Empty when the fixture returned no text.
  final String text;

  /// The in-band error flag. `false` here is MCP's null-or-false success.
  final bool isError;
}

/// Replies copied from mcp_probe's well-behaved fixture.
///
/// `echo` returns the `text` argument; `fail_tool` always sets `isError`
/// with "intentional failure"; `read_env` is `MCP_PROBE_ENV` or empty;
/// the greeting resource is "hello from fixture"; the greet prompt is
/// "Please greet ${name}.".
const echoKey = 'tools/call echo {"text":"The capital of France is Paris."}';
const failToolKey = 'tools/call fail_tool {}';
const readEnvKey = 'tools/call read_env {}';
const greetingKey = 'resources/read probe://greeting';
const greetKey = 'prompts/get greet {"name":"Ada"}';

const recorded = <String, RecordedTurn>{
  echoKey: RecordedTurn(
    method: echoKey,
    text: 'The capital of France is Paris.',
  ),
  failToolKey: RecordedTurn(
    method: failToolKey,
    text: 'intentional failure',
    isError: true,
  ),
  readEnvKey: RecordedTurn(method: readEnvKey, text: ''),
  greetingKey: RecordedTurn(method: greetingKey, text: 'hello from fixture'),
  greetKey: RecordedTurn(method: greetKey, text: 'Please greet Ada.'),
};

/// Returns the recorded text, throwing on `isError`.
///
/// This is the mapping that treats a tool which reported failure as "no
/// output was produced" — an `AttemptResult.modelError`, not a failed
/// check. The blind flattening (`toolTextBlind`) is the other mapping;
/// both run against `fail_tool` after the main suite.
Future<String> toolText(String prompt) async {
  final turn = recorded[prompt];
  if (turn == null) {
    throw StateError('no recorded turn for $prompt');
  }
  if (turn.isError) {
    throw StateError('MCP tool reported isError: ${turn.text}');
  }
  return turn.text;
}

/// Returns the recorded text even when `isError` is set.
Future<String> toolTextBlind(String prompt) async {
  final turn = recorded[prompt];
  if (turn == null) {
    throw StateError('no recorded turn for $prompt');
  }
  return turn.text;
}

Future<void> main() async {
  final suite = EvalSuite([
    EvalCase(
      id: 'echo-payload',
      prompt: echoKey,
      checks: [
        // The evaluation question: is the text this tool handed a model
        // actually usable as context for the question that triggered it?
        Check.contains('paris'),
        Check.contains('france'),
        Check.notContains('intentional failure'),
      ],
    ),
    EvalCase(
      id: 'greeting-resource',
      prompt: greetingKey,
      checks: [
        Check.contains('hello'),
        Check.predicate(
          'short enough to stuff into a prompt',
          (output) => output.isNotEmpty && output.length < 80,
        ),
      ],
    ),
    EvalCase(
      id: 'greet-prompt',
      prompt: greetKey,
      checks: [
        Check.contains('Ada', caseSensitive: true),
        Check.matches(RegExp(r'Please greet')),
      ],
    ),
    EvalCase(
      id: 'read-env-unset',
      prompt: readEnvKey,
      checks: [
        // Empty tool text is a real eval: a model that consumes it sees
        // nothing. The fixture returns '' when MCP_PROBE_ENV is unset,
        // which is this recording.
        Check.predicate('empty when MCP_PROBE_ENV is unset', (o) => o.isEmpty),
      ],
    ),
  ]);

  final report = await suite.run(toolText, modelId: 'mcp-fixture-transcript');
  stdout.writeln(report.toMarkdown());

  // fail_tool, both mappings, against the real API rather than a sketch.
  final flattened = await EvalSuite([
    EvalCase(
      id: 'fail-tool-flattened',
      prompt: failToolKey,
      checks: [Check.contains('intentional failure')],
    ),
  ]).run(toolTextBlind, modelId: 'mcp-fixture-transcript');

  final thrown = await EvalSuite([
    EvalCase(
      id: 'fail-tool-thrown',
      prompt: failToolKey,
      checks: [Check.contains('intentional failure')],
    ),
  ]).run(toolText, modelId: 'mcp-fixture-transcript');

  final flatCase = flattened.results.single;
  final throwCase = thrown.results.single;
  stdout.writeln('## fail_tool, two mappings');
  stdout.writeln();
  stdout.writeln(
    'The fixture sets `isError: true` and returns "intentional '
    'failure". Flatten that string into a check and the eval is green '
    'on a tool that failed. Throw it and llm_eval records an error, '
    'which is not a failed check and must not be folded into the '
    'pass rate.',
  );
  stdout.writeln();
  stdout.writeln(
    '- flattened: ${_status(flatCase)}  '
    'passRate ${flattened.passRate}  '
    'errorCount ${flattened.errorCount}',
  );
  stdout.writeln(
    '- thrown:    ${_status(throwCase)}  '
    'passRate ${thrown.passRate}  '
    'errorCount ${thrown.errorCount}',
  );
  stdout.writeln();

  final failed = report.results.where((r) => !r.passed).length;
  stdout.writeln('${report.passedCount}/${report.results.length} cases passed');
  exitCode = failed == 0 ? 0 : 1;
}

String _status(CaseResult r) {
  if (r.hasError) return 'error';
  return r.passed ? 'pass' : 'fail';
}
