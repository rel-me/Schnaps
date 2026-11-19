# User request

When I start Find Dimensions it seems to not be clearing the dimensions sometimes on refresh.
I think maybe there are SwiftUI bugs and we should migrate that code the AppKit.

# Delegated PR monitoring prompt

Monitor the PR for branch `codex/gabriel/clear-find-dimensions-on-refresh` in `rel-me/Schnaps` once it opens. Wait for both macOS CI jobs on the latest head. Diagnose failures, fix any caused by this change in the shared checkout, run relevant tests, commit and push, and repeat monitoring on the updated head. Preserve unrelated changes and leave the PR open. Report the final head and check results.

# Follow-up user request

it seems like it's leaving a crosshair whenever Find Dimensions is activated

The attached screenshot shows a small pink crosshair with a light outline.

# Follow-up delegated PR monitoring prompt

Monitor the updated head of PR #106 in `rel-me/Schnaps` after the Find Dimensions crosshair redraw fix is pushed. Wait for both macOS CI jobs. Diagnose failures, fix any caused by this change in the shared checkout, run relevant tests, commit and push, and monitor each updated head. Preserve unrelated changes and leave the PR open. Report the final head and check results.
