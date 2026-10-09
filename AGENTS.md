# Repository maintenance

For user-requested changes, keep GitHub records current as part of completing the work:

- Update CHANGELOG.md with user-visible changes and relevant validation or limits.
- Keep README and macOS/FEATURES.md consistent with shipped behavior and version labels.
- Run checks appropriate to the changed platform; record results in the commit or PR.
- Commit changes in coherent groups and push a codex/ branch with a descriptive PR.
  Inspect existing PRs first and update the matching PR when accessible.
- Verify remote writes before reporting completion. Report access or CI failures plainly.
- Keep local libraries, credentials, QA app copies and build outputs out of Git.
- Do not merge PRs or publish releases unless the user authorizes that action.
