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
