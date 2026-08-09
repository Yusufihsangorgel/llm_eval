// LLM as judge, in one file.
//
// The other two examples check properties you can spell out: a substring, a
// regexp, valid JSON, a predicate over the string. This one is about the
// properties you can only recognise by reading the answer. Did the summary
// keep the caveat the source had? Would you send this reply to a customer who
// has been waiting nine days? Nobody writes those as a predicate.
// `Check.judge` hands the output to a second model along with a rubric and
// turns the score that comes back into a verdict.
//
// Run it:
//
//   dart run example/judge.dart
//
// Three cases, and only the first is the happy path:
//
//   1. summary-keeps-caveat   judge scores 0.9, at or above passAt -> pass
//   2. refund-reply-tone      judge scores 0.4, below passAt       -> fail
//   3. currency-is-explicit   judge answers in prose, no score     -> error
//
// The third case is why this file exists. A judge is a language model that
// has been asked to answer in a fixed format, and some fraction of the time
// it answers in prose instead. There is no number to read in that reply and
// llm_eval will not invent one. The case lands in the report as an error,
// which is its own column, separate from a fail. `ci_gate.dart` shows what a
// build step does with that distinction.

import 'dart:io';

import 'package:llm_eval/llm_eval.dart';

/// Calls made to the model under test during this run.
var modelCalls = 0;

/// Calls made to the judge during this run.
///
/// A judge check costs a second model call per case. That is the price of the
/// feature, and it is worth seeing next to the first number before you put a
/// judge on every case in a large suite.
var judgeCalls = 0;

/// Stands in for the model under test, so this example needs no key and no
/// network. In a real project this is your OpenAI, Anthropic, Gemini or
/// Ollama call, and nothing else on this page changes.
Future<String> supportBot(String prompt) async {
  modelCalls++;

  if (prompt.contains('changelog')) {
    return 'Timeouts are retried once. The retry is best effort and can '
        'duplicate a write.';
  }

  if (prompt.contains('refund')) {
    // Correct and unsendable. Every fact in it is right, which is why no
    // substring check is going to catch what is wrong with it.
    return 'This was already answered. Refunds take up to ten business days '
        'from approval, as our terms state. Please read them before '
        'contacting support again.';
  }

  return 'The balance is 240.50 and settles tomorrow.';
}

/// Stands in for the judge, which in a real suite is usually a stronger model
/// than the one under test.
///
/// It receives the prompt `Check.judge` builds: the rubric, the output between
/// `=====` lines, and the instruction to answer with a single
/// `SCORE: <number>` line. Branching on a phrase from the rubric is what keeps
/// this fake deterministic; a real judge reads both halves and decides.
Future<String> reviewer(String prompt) async {
  judgeCalls++;

  if (prompt.contains('keeps the warning')) {
    // A judge may explain itself on the lines after the score. llm_eval reads
    // the score line and leaves the prose alone.
    return 'SCORE: 0.9\n'
        'Both sentences survive, including the duplicate-write warning.';
  }

  if (prompt.contains('never implies the customer')) {
    return 'SCORE: 0.4\n'
        'The ten-day window is there. The apology is missing, and the last '
        'sentence puts the delay on the customer.';
  }

  // Off script: a plausible, even useful sentence with no score anywhere in
  // it. This is the reply that becomes an error result.
  return 'Hard to say. The number looks right, but I would want the currency '
      'spelled out before signing off.';
}

Future<void> main() async {
  final suite = EvalSuite([
    EvalCase(
      id: 'summary-keeps-caveat',
      prompt:
          'Summarise for a changelog: "Timeouts are retried once. '
          'Retries are best effort and can duplicate a write."',
      checks: [
        // The half of the requirement you can spell out, next to the half you
        // cannot. Reach for the judge only for the second one: each judge
        // check is another model call and another thing that can go wrong.
        Check.contains('duplicate'),
        Check.judge(
          judge: reviewer,
          rubric:
              'The summary keeps the warning that a retry can duplicate a '
              'write.',
          passAt: 0.7,
        ),
      ],
    ),
    EvalCase(
      id: 'refund-reply-tone',
      prompt:
          'A customer approved for a refund nine days ago asks where it '
          'is. Write the reply.',
      checks: [
        Check.judge(
          judge: reviewer,
          rubric:
              'The reply gives the ten-day window, apologises for the wait, '
              'and never implies the customer should have known.',
          // The judge returns 0.4. The case fails, and the report prints that
          // score beside the threshold that rejected it, which is the part
          // that tells you whether to fix the prompt or move the threshold.
          passAt: 0.7,
        ),
      ],
    ),
    EvalCase(
      id: 'currency-is-explicit',
      prompt: 'Tell the user their balance and when it settles.',
      checks: [
        Check.judge(
          judge: reviewer,
          rubric: 'The answer says which currency the amount is in.',
          // passAt keeps its default here because nothing ever compares
          // against it: a reply with no score line is an error before any
          // threshold gets applied.
        ),
      ],
    ),
  ]);

  final report = await suite.run(supportBot, modelId: 'support-bot-v3');
  stdout.writeln(report.toMarkdown());

  // One call to each model per case. `suite.run`'s cache covers the first
  // number only. The judge runs inside a check, one level further down, and
  // never reaches that cache; `cache.wrap(reviewer, modelId: 'reviewer-v1')`
  // gives it one of its own.
  stdout.writeln('model calls: $modelCalls   judge calls: $judgeCalls');
}
