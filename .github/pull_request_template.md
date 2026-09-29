Issue: #<number>

Checklist, matching CI. Run in the repository root:

- [ ] `dart pub get`
- [ ] `dart format --output=none --set-exit-if-changed .`
- [ ] `dart analyze --fatal-infos`
- [ ] `dart test`
- [ ] `dart run tool/eval.dart`
- [ ] `cat eval-report.md >> "$GITHUB_STEP_SUMMARY"`
- [ ] `CHANGELOG.md` entry added
