# User request

```text
Schnap on main
❯ make beta
xcrun: error: missing DEVELOPER_DIR path: /Applications/Xcode_26.3.app/Contents/Developer
```

# Repository instructions

Create a branch and PR; commit and push changes. Delegate PR monitoring and failure fixes to a sub-agent. Log requests and delegated prompts under docs/prompts.

# Delegated PR monitoring prompt

Monitor the PR for branch codex/gabriel/fix-xcode-path in rel-me/Schnaps until all CI checks finish. Investigate and fix failures caused by this change, log follow-up delegated prompts in this file, commit and push fixes, and monitor each updated PR head again. Use env -u DEVELOPER_DIR -u SCHNAPS_XCODE_VERSION for local mise commands to clear inherited stale environment values. Do not merge or publish a release. Report final check results and any blockers.
