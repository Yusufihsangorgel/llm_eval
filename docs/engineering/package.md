# Package engineering rules: llm_eval

Rules-Version: llm_eval/c3b56cd0a2d09fbe9c89711adc896a0e495101e01f042e3ffe48b4356c6a3d55
Core-Version: 1
Core-Digest: 1825fa7ff346dca23e65b1b3bf9b2e3e06959f1414bae9952d596d2f62f09b8f
Survey-Digest: f90f45c8a172068c3ed3b9488ba5a7cb4e58efa93c380d2d9a70b399349ec35e
Evidence-Revision: d74b0f7
Verified-Revision: unverified

Read CONTRIBUTING.md and docs/engineering/debt.json before editing.

## Current architecture
A test harness for LLM outputs. The platform-independent core (lib/llm_eval.dart) and the file cache that needs dart:io/crypto (lib/io.dart) are separate. The package ships no model client: the ModelCall typedef, the ResponseCache interface, and the Check interface are the seams. The flow: EvalSuite.run (worker pool concurrency, cache, repeat) → Check (interface + factory constructors + private implementations, including an LLM judge) → CheckResult (pass/fail/error tri-state) → EvalReport (JSON, Markdown, JUnit XML) → baseline.dart (EvalBaseline, identity-based regression detection with diffAgainstBaseline). Every error at the user code boundary lands in the report as an error. The run keeps going. The package runs an eval gate in its own CI, replayed from a committed cache (tool/eval.dart, tool/eval_cache/). Scanned HEAD: d74b0f7 (version 1.3.2).

## Layers and responsibilities
- lib/llm_eval.dart, lib/io.dart: Core names with `show`. FileResponseCache comes from a separate entry library.
- lib/src/model_call.dart, lib/src/response_cache.dart, lib/src/check.dart (Check interface): Model call typedef, cache interface + wrap extension for nested calls, check interface.
- lib/src/eval_case.dart, lib/src/check_result.dart, lib/src/eval_report.dart, lib/src/baseline.dart: Case definition, tri-state result, attempt/case/report, report formatters, baseline and diff.
- lib/src/eval_suite.dart, lib/src/check.dart (private implementations), lib/src/error_detail.dart: Concurrent run, cache read/write, error→report conversion, built-in checks, single-line error text.
- lib/src/file_response_cache.dart: A file cache with SHA-256 file names and atomic writes.
- tool/eval.dart, tool/eval_cache/, tool/baseline_figure.dart: A replay-only eval gate and a README figure.
- example/, test/: Examples with fake models, unit tests, validation of JUnit output with xml.

## Public API and dependency direction
lib/llm_eval.dart exposes with `show`: BaselineCase, CaseChange, EvalBaseline, EvalDiff, diffAgainstBaseline; Check; CheckResult; EvalCase; AttemptResult, CaseResult, CheckOutcome, EvalReport; EvalSuite; ModelCall; NestedModelCallCaching, ResponseCache (llm_eval.dart:12-21). lib/io.dart: FileResponseCache (io.dart:13). Not exported: describeError (error_detail.dart). Extension points: `abstract interface class Check` (check.dart:14), `abstract interface class ResponseCache` (response_cache.dart:13), `typedef ModelCall` (model_call.dart:10). Wire contracts: the cache key format and SHA-256 file name, baseline JSON (version 1), the report JSON/JUnit/Markdown formats. The baseline.dart classes are not final (debt).

eval_suite.dart → check_result, error_detail, eval_case, eval_report, model_call, response_cache (1-6). check.dart → check_result, error_detail, model_call (1-6). eval_case.dart → check. baseline.dart → eval_report. eval_report.dart → check_result. response_cache.dart → model_call. file_response_cache.dart → response_cache + dart:io + package:crypto (1-6). dart:io and crypto appear only in file_response_cache.dart. That file is exported only from io.dart. No cycles. xml is dev only (junit test).

## Error, state and platform contracts
- Interface + factory constructors + private implementation classes (check.dart:14-93, 95-315).
- Tri-state result: fail and error stay separate. Broken harness code does not look like a failing model (check_result.dart:1-52).
- User code boundary: model, predicate, where, and judge calls are wrapped and turned into an error result with describeError. A cache read error counts as a miss. A cache write error counts as a model error (eval_suite.dart:120-165; check.dart:191-197, 216-222, 277-283).
- Length-prefixed cache key, pinned by tests (eval_suite.dart:116-117; test/cache_test.dart:97, 323).
- Copy + unmodifiable on input types (eval_case.dart:9-15; eval_suite.dart:14).
- No machine paths in report text. Stack frames are shortened (error_detail.dart:7-12, 26-37).
- Using the package in its own CI: a replay-only eval gate. A miss fails the job (ci.yaml:27-38; tool/eval.dart:9-22).
- Atomic file writes: temp file + rename (file_response_cache.dart:15-17, 39-45).

## Package rules
### llm_eval/EVAL-01 [MUST]
lib/llm_eval.dart and every file it exports stay free of dart:io and package:crypto. File-backed code is exported only from lib/io.dart.
Reason: The core's claim of running on every platform (including web) rests on this split.
Evidence: lib/llm_eval.dart:7-9; lib/io.dart:1-13; lib/src/file_response_cache.dart:1-6; lib/src/response_cache.dart:10-12
Evidence role: current-pattern
Existing violation: none

### llm_eval/EVAL-02 [MUST_NOT]
Do not ship a model client. Models, judges and caches arrive through `ModelCall` and `ResponseCache`.
Reason: The package's architectural decision: a provider-independent harness, and the caller wires the client.
Evidence: lib/src/model_call.dart:4-10; lib/src/response_cache.dart:13-19
Evidence role: current-pattern
Existing violation: none

### llm_eval/EVAL-03 [MUST]
When the harness calls caller code (model, check predicate, `where`, judge), anything thrown becomes an error result built with `describeError`. A failed cache read counts as a miss and a failed cache write as a model error. The run never aborts, and an error never counts as a pass or a fail.
Reason: Documented contract. This user-code boundary is the named exception to the shared typed catch rule (J10).
Evidence: lib/src/eval_suite.dart:28-31, 39-41, 120-165; lib/src/check.dart:48-50, 191-197, 216-222, 277-283; lib/src/response_cache.dart:45-58
Evidence role: current-pattern
Existing violation: none

### llm_eval/EVAL-04 [MUST]
A check that cannot reach a verdict returns `CheckResult.error`, never a pass or a fail.
Reason: A broken harness must not be reported like a failing model. There is no silent fallback for judge output.
Evidence: lib/src/check_result.dart:1-13; lib/src/check.dart:72-75, 284-303
Evidence role: current-pattern
Existing violation: none

### llm_eval/EVAL-05 [MUST]
A new built-in check is a private class behind a factory constructor on `Check`, with a `description` that reads as a report label.
Reason: The current six checks are written this way. The report and the baseline key a check by its description.
Evidence: lib/src/check.dart:10-13, 28-92, 95-127; lib/src/baseline.dart:24-28
Evidence role: current-pattern
Existing violation: none

### llm_eval/EVAL-06 [MUST_NOT]
Do not change the cache key (`<label length>:<label>`, a newline, then the prompt) or the `FileResponseCache` file naming outside a major version. Committed caches, tool/eval_cache/ included, depend on both.
Reason: If the key changes, every committed cache silently becomes invalid and the CI gate breaks.
Evidence: lib/src/eval_suite.dart:116-117; lib/src/response_cache.dart:39-43, 51-52; lib/src/file_response_cache.dart:10-11, 26-29; test/cache_test.dart:97, 323; tool/eval.dart:33-40
Evidence role: current-pattern
Existing violation: none

### llm_eval/EVAL-07 [MUST]
Public classes are `final`. Types that take caller input, as `EvalCase` and `EvalSuite` do, copy caller collections into unmodifiable ones.
Reason: In the 1.0 freeze the value types were sealed and the inputs were copied. Baseline classes added later break this (debt).
Evidence: lib/src/eval_case.dart:4, 9-15; lib/src/eval_suite.dart:9-14; lib/src/eval_report.dart:4, 16, 60, 89; commit 6d049df, 2c489a5; counterexample lib/src/baseline.dart:6, 82, 140, 155
Evidence role: both
Existing violation: llm_eval-D002

### llm_eval/EVAL-08 [MUST]
Report text never carries an absolute path from the machine that ran the suite. Error strings go through `describeError`.
Reason: Reports get pasted into PRs and work summaries. Machine paths create noise and leakage.
Evidence: lib/src/error_detail.dart:7-12, 26-37; CHANGELOG.md:26-27; lib/src/eval_suite.dart:138, 151
Evidence role: current-pattern
Existing violation: none

### llm_eval/EVAL-09 [MUST]
The CI eval gate replays only. A cache miss fails the job, and recording needs `--record` on a developer machine.
Reason: The gate must stay deterministic, free, and independent of provider availability.
Evidence: .github/workflows/ci.yaml:27-38; tool/eval.dart:9-22
Evidence role: current-pattern
Existing violation: none

### llm_eval/EVAL-10 [MUST]
A behavior change lands with a CHANGELOG entry and a test in the same commit.
Reason: Repository practice: behavior commits carry both together.
Evidence: commit ac4f131, ec2c61a, 21cd755, 5baa49d, 2c489a5 (CHANGELOG + test)
Evidence role: current-pattern
Existing violation: none

### llm_eval/EVAL-11 [MUST]
Export public names with a `show` list from lib/llm_eval.dart or lib/io.dart. Tests import these libraries, and a test may import a file under lib/src/ only for a helper that is not exported.
Reason: Barrel naming was done in 1.0. Testing an internal helper is the single deliberate exception.
Evidence: lib/llm_eval.dart:12-21; lib/io.dart:13; commit 6d049df; test/error_detail_test.dart:1
Evidence role: current-pattern
Existing violation: none

### llm_eval/EVAL-12 [SHOULD]
Dartdoc describes current behavior. Plans go to the Planned section of the README, not to member docs.
Reason: The README already has a plan list. The untracked promise in the member docs is not even in that list.
Evidence: README.md:399-408; counterexample lib/src/eval_suite.dart:43-45
Evidence role: both
Existing violation: llm_eval-D010

## Required verification
- Working directory: repository root; command: dart pub get; conditions: ci.yaml job build; evidence: .github/workflows/ci.yaml:22.
- Working directory: repository root; command: dart format --output=none --set-exit-if-changed .; conditions: ci.yaml job build; evidence: .github/workflows/ci.yaml:23.
- Working directory: repository root; command: dart analyze --fatal-infos; conditions: ci.yaml job build; evidence: .github/workflows/ci.yaml:24.
- Working directory: repository root; command: dart test; conditions: ci.yaml job build; evidence: .github/workflows/ci.yaml:25.
- Working directory: repository root; command: dart run tool/eval.dart; conditions: ci.yaml job build; evidence: .github/workflows/ci.yaml:38.
- Working directory: repository root; command: cat eval-report.md >> "$GITHUB_STEP_SUMMARY"; conditions: ci.yaml job build; evidence: .github/workflows/ci.yaml:44.
Not verified by the survey:
- The scan used the local HEAD (d74b0f7). Equality with origin and uncommitted changes were not measured.
- Cognitive complexity scores were not measured. Candidates: eval_suite.dart:109-176 (_runAttempt), baseline.dart:248-328 (diffAgainstBaseline), eval_report.dart:335-407 (toMarkdown).
- Whether tests pass on the web and the current test status: `dart test` was not run.
- Whether the e2e test exceeds the default 30 s timeout when Ollama is present was not measured.

## Existing debt
The complete register is docs/engineering/debt.json.
- llm_eval-D001 | small | lib/src/eval_suite.dart:116-117; lib/src/response_cache.dart:51-52 | duplicated logic (with a 'keep in sync' comment)
  Fix: A single private `cacheKey(label, prompt)` function (in response_cache.dart); both sites should use it. test/cache_test.dart:97 and 323 already pin the format.
  Closure: A single private cacheKey function in response_cache.dart builds the key and both call sites use it. test/cache_test.dart passes and still pins the format at its cases 97 and 323.
- llm_eval-D002 | large | lib/src/baseline.dart:6, 82, 140, 155 (and 84-87, 157-166) | leaking public API
  Fix: In 2.0: `final class`, unmodifiable copies, and freeze tests. Keep it on the record until then.
  Closure: In 2.0 the four baseline classes are final class and copy caller collections into unmodifiable ones. Freeze tests pin the copies.
- llm_eval-D003 | small | lib/src/baseline.dart:112, 118-129 | half-implemented contract
  Fix: Make fromJson validate the version (1 if the field is missing, FormatException on an unknown version) and add a test.
  Closure: fromJson treats a missing version field as 1 and throws FormatException on an unknown version. A test covers both paths.
- llm_eval-D004 | small | lib/src/baseline.dart:31-54, 96-108 | untyped internal path
  Fix: Build fromReport through CaseResult/AttemptResult/CheckOutcome. Keep fromReportJson for file reading. Safety net: baseline_test.dart.
  Closure: EvalBaseline.fromReport builds from CaseResult, AttemptResult and CheckOutcome values without re-parsing report.toJson. baseline_test.dart passes and fromReportJson still reads files.
- llm_eval-D005 | small | lib/src/file_response_cache.dart:24 | undocumented global mutable state
  Fix: Write the rationale in the dartdoc or use a unique suffix that needs no shared state.
  Closure: The static counter carries a dartdoc rationale or the temporary file names use a suffix that needs no shared state.
- llm_eval-D006 | small | dart_test.yaml:1-3; test/ollama_e2e_test.dart:1-12 | dead configuration
  Fix: Add `@Tags(['e2e'])` and `library;` to the test (as in instructor_dart).
  Closure: test/ollama_e2e_test.dart starts with library; and carries @Tags(['e2e']). Running dart test --exclude-tags e2e skips it.
- llm_eval-D007 | medium | lib/src/eval_report.dart:139-407 | single responsibility violation
  Fix: Move JUnit and Markdown generation to private lib/src files and let the existing methods call them. The public API stays unchanged. Safety net: report_test.dart and junit_xml_test.dart.
  Closure: JUnit XML and Markdown generation live in private lib/src files and the EvalReport methods call them. report_test.dart and junit_xml_test.dart pass.
- llm_eval-D008 | small | lib/src/check.dart:271-272 | unnamed operational constant
  Fix: A named const and a one-sentence rationale.
  Closure: The quote limit is a named const with a one-sentence rationale at its definition.
- llm_eval-D009 | small | lib/src/eval_suite.dart:123, 131, 145, 163; lib/src/check.dart:193, 218, 279; lib/src/response_cache.dart:56 | untyped catch
  Fix: `on Object catch` with a one-line rationale. Name the exception in the EVAL-03 rule.
  Closure: All listed catch sites read on Object catch with a one-line rationale comment. The EVAL-03 rule text names the exception.
- llm_eval-D010 | small | lib/src/eval_suite.dart:43-45 | untracked promise
  Fix: The dartdoc should describe only current behavior. Move the plan to the README Planned section or to an issue.
  Closure: The eval_suite.dart dartdoc describes only current behavior. The deduplication plan appears in the README Planned section or a tracked issue.
- llm_eval-D011 | small | .github/workflows/ci.yaml:22-25; lib/llm_eval.dart:7-9 | unverified platform claim
  Fix: Add `dart test -p chrome` to CI. Put `@TestOn('vm')` on the tests that use dart:io (cache_test, ollama_e2e_test).
  Closure: ci.yaml runs dart test -p chrome and the run passes. The tests that use dart:io carry @TestOn('vm').
