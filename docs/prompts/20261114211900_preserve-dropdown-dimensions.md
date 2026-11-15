# User request

“If I have a dropdown showing and I active with Find Dimensions, the dropdown goes away”

# Repository instructions

Create a branch and PR, commit and push changes, and delegate PR monitoring and failure fixes to a sub-agent. Log user requests and delegated prompts under `docs/prompts/` and append follow-ups for this change.

# Change

Show nonactivating measurement panels immediately, keeping them unable to take keyboard/main focus while the initial frozen screenshot is pending. Install and display the screenshots before activating Schnaps. Restore keyboard handling after failed or unavailable capture, and ignore cancelled startup completions. Live mode retains immediate focus.

# Validation

`swift test` passed: 96 Swift Testing tests plus one XCTest. `git diff --check` passed. Regression coverage checks focus suppression before capture, cancelled-capture isolation, focus restoration after the frozen image is installed, and fallback keyboard handling when capture fails or permission is unavailable.

# Delegated PR monitoring prompt

Monitor the PR for branch codex/gabriel/preserve-dropdown-dimensions until all checks finish. Inspect failures caused by this change, fix them, run relevant validation, commit and push fixes, then monitor the new head again until it passes. Append delegated follow-up prompts to docs/prompts/20261114211900_preserve-dropdown-dimensions.md. Do not merge. Report final checks and any changes.
