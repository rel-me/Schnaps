# User request

The rulers positioning overlay can appear over the ruler itself

# Repository instructions

Create a branch and PR. Commit and push changes when completing a task. If there are no code changes, don't create a PR. In a sub-agent, monitor the PR and fix failures. If a PR changes after a successful run, monitor the PR again in a sub-agent to make sure it passes.

Log each change's user requests and delegated prompts in a separate file under `docs/prompts/`, named `YYYYMMDDHHMMSS_{short-prompt-name}.md`. Use the current local time in 24-hour format for the sortable prefix and a descriptive lowercase hyphenated name. Append follow-up prompts for the same change to that file.

# Delegated PR monitoring prompt

Monitor the PR for branch `codex/gabriel/ruler-caption-placement` in `rel-me/Schnaps` until all checks finish. Inspect failures and fix any failures caused by this change in the shared checkout. Run relevant checks, commit and push fixes, and monitor the updated PR again until it passes. Do not merge. Preserve unrelated work. If fixes are needed, append their context and any further delegated prompts to this prompt log. Report the final head commit, check results, and any external blockers. Use bounded waits and send a progress update if checks take more than a minute.
