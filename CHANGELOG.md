## 1.2.0

- The README now answers, in its first screen, why to reach for this rather
  than the zero-dependency route or the package that already owns the
  category. Both answers carry the file and line, or the issue number, that
  a reader can check. A "reach for it when" list and a sentence on when to
  skip it follow, because a page that only argues for itself is not useful
  for deciding.

## 1.1.1

- The baseline section opens on a picture. `tool/baseline_figure.dart` runs two
  evals that land on the same 75% pass rate, one of which broke a case while
  another was fixed, and draws `doc/baseline-diff.png` from the diff it gets
  back. The generator refuses to write the file if the two runs stop agreeing
  on the rate, which keeps the figure from outliving the claim it illustrates.
- Drop `doc/judge-cache.png`. Nothing referenced it and it was 162 KB of every
  download.

## 1.1.0

- Add `EvalBaseline` and `diffAgainstBaseline`. A pass-rate threshold cannot
  see composition: nine of ten passing before and nine of ten now is the same
  number whether nothing moved or one case broke while another was fixed, and
  deleting the failing case moves the rate exactly the way repairing it does.
  A baseline keeps the identity of what passed, and the diff names what
  changed.
- `EvalDiff.hasRegressions` stops for four things: a case that stopped
  passing, a score that fell past the tolerance while the case still passed, a
  case that was steady and now disagrees between attempts, and a case that is
  in the baseline and missing from the run. Fixes and new cases are reported
  without stopping the build.
- A baseline records the lowest score each check reached across the attempts
  of one case, which is the number a threshold would have tripped on. Keeping
  the last would let a bad attempt hide behind a good one that ran second.
- `toJsonString` and `EvalBaseline.parse` are the round trip for a file
  committed next to your tests. `toMarkdown` renders the diff for a CI log and
  names a model change when the baseline and the run disagree about the model.

## 1.0.2

- `example/judge.dart` runs `Check.judge`. The README answers the part of a
  model's reply no assertion can pin down with a judge, and neither example
  called one. The new file scores an answer against a rubric with a scripted
  judge, no network and no key. Docs and example only.

## 1.0.1

- **Put the screenshot caption on one line.** It was a folded scalar wrapped
  mid-word, and a folded scalar turns the line break into a space, so pub.dev
  has been rendering `checks o utputs` since the caption was added. The figure
  is unchanged.

- Gate this package's own CI on an eval suite. `tool/eval.dart` runs four cases
  and replays every response from the committed `tool/eval_cache/`, so the job
  makes no model calls and a regression fails it rather than a network blip.
  The harness is now exercised by the kind of thing it exists for, not only by
  unit tests.

- Add `example/ci_gate.dart`, an end-to-end suite that runs in CI, and fill out
  the README around it.

- Move the `xml` dev dependency to `^7.0.0`.

`lib/` is byte-identical to 1.0.0. Nothing here changes the API.

## 1.0.0

The API is stable. One freeze-blocker was left, found by adversarially testing
the harness rather than reading it, and it is fixed here.

- **`EvalCase` and `EvalSuite` now copy the collections they are given.**
  `EvalCase.checks`, `EvalCase.metadata` and `EvalSuite.cases` aliased the
  caller's list or map, so mutating what you passed in after construction
  silently changed the case or suite — adding a case to the original list added
  it to the suite's run. They are now copied to unmodifiable collections at
  construction. This is the shape of bug (a constructor keeping a live reference
  to a caller-owned collection) that has to be settled before a 1.0.0 freeze.

Everything else was verified by execution and left unchanged: an empty suite, a
check that throws, and a model that throws are all handled without crashing; the
`FileResponseCache` sanitises keys so a path-hostile key cannot escape its
directory, survives concurrent writes to one key without corruption, and
round-trips empty and unicode values. The only runtime dependency is `crypto`.

Types are `final` (`Check` and `ResponseCache` stay implementable, since that is
how you add your own), and the barrel files name what they export.

## 0.4.1

- Add `example/README.md` for pub.dev's Example tab (it was empty). It walks
  through the example suite — cases, checks, and the Markdown report — against
  the fake deterministic model, with the real output. Docs only.

## 0.4.0

Freeze hygiene ahead of 1.0.0. No behaviour changes; both items are about what
the package promises rather than what it does.

- **The barrel files now name what they export.** `llm_eval.dart` and `io.dart`
  re-exported whole source files, which meant every public name in them was
  API by accident, and any name added later would have become API silently.
  They now list exactly what they export. The exported set is unchanged —
  including the `NestedModelCallCaching` extension on `ResponseCache`, which
  the first draft of this change would have dropped and which the tests caught.
- **The value types are `final`.** `AttemptResult`, `CaseResult`,
  `CheckOutcome`, `EvalReport`, `EvalSuite`, `EvalCase`, `CheckResult` and
  `FileResponseCache` carried no class modifier, so freezing them would have
  made every future parameter a breaking change for anyone who had subclassed
  them. Nothing in the package, its tests or its example subtypes any of them.
  `Check` stays an `abstract interface class`: implementing it is how callers
  add their own checks, and `ResponseCache` stays implementable for the same
  reason.

## 0.3.1

- `Check.isValidJson` now strips a single wrapping markdown code fence before
  giving up. Chat-tuned models commonly answer a JSON prompt with the answer
  wrapped in a code fence (optionally tagged `json`) unless the caller forces
  a JSON-only response mode, and the raw `jsonDecode` call was failing on
  exactly that output, reporting a fail on a correct answer instead of a
  pass.

## 0.3.0

- Add `ResponseCache.wrap`, a caching wrapper for a nested `ModelCall`.
  `EvalSuite.run` caches the model under test but never the judge in a
  `Check.judge`, so a warm cache used to skip the model and still call the
  judge on every run, breaking the deterministic and free promise while the
  report labeled the case cached. Wrap the judge with
  `cache.wrap(judgeModel, modelId: 'judge-v1')` and it caches under the same
  key scheme the suite uses. Also documented that `fromCache` and the report's
  `cached` column describe the model under test, not any nested judge.

## 0.2.2

- Shorten the screenshot description. pub.dev accepts up to 200 characters but
  scores only those under 160, so the previous release published cleanly and
  quietly gave up the documentation points it was meant to earn.

## 0.2.1

- Declare the diagram in `pubspec.yaml` so pub.dev renders it on the package
  page. It was already in the repository and the README, but pub.dev shows only
  what the `screenshots:` field points at, so the page opened with prose where
  the picture should have been.

## 0.2.0

- Add `EvalReport.toJUnitXml()`. The exit-code gate added in 0.1.3 turns a
  build red; this makes the CI system show which cases went red and why. Each
  eval case becomes a `<testcase>`, a model error or errored check becomes an
  `<error>`, any other non-passing case a `<failure>` carrying the checks that
  failed and the model output that failed them, and a flaky case reports how
  many attempts passed. GitHub Actions, GitLab, Jenkins, CircleCI and
  Buildkite all read this format. Model output is arbitrary text, so it is
  XML-escaped and characters XML 1.0 does not permit are dropped rather than
  emitted; one stray control byte would otherwise make a parser reject the
  whole report.

## 0.1.3

- Example: use the suite as a CI gate. It now exits non-zero when any case
  fails, the way you wire it into a build step, instead of only printing a
  report.

## 0.1.2

- Docs: sharpen the pub.dev description to lead with the value and the terms people search.

## 0.1.1

- Docs: tightened the README wording and visuals.

# Changelog

## 0.1.0

Initial release.

- `EvalCase`, `EvalSuite`, and `EvalReport` with Markdown and JSON output.
- Built-in checks: `contains`, `notContains`, `matches`, `isValidJson`,
  `predicate`, and LLM-as-judge scoring with `Check.judge`.
- `ResponseCache` interface in the core and a file-backed
  `FileResponseCache` in `package:llm_eval/io.dart` (atomic writes) for
  deterministic reruns in CI.
- Concurrent case execution with stable result order.
- Repeat runs with a flakiness rate.
