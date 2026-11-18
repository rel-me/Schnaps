# User request

Is there a cool way to adjust the find dimensions tolerance while it is up... show the tolerance in the overlay label.. can mouse scroll up down change that? and keyboard shortcut too

# Repository instructions

Create a branch and PR. Commit and push changes when completing a task. If there are no code changes, don't create a PR. In a sub-agent, monitor the PR and fix failures. If a PR changes after a successful run, monitor the PR again in a sub-agent to make sure it passes.

Log each change's user requests and delegated prompts in a separate file under `docs/prompts/`, named `YYYYMMDDHHMMSS_{short-prompt-name}.md`. Use the current local time in 24-hour format for the sortable prefix and a descriptive lowercase hyphenated name. Append follow-up prompts for the same change to that file.

# Delegated PR monitoring prompt

Monitor the PR for branch `codex/gabriel/find-dimensions-tolerance-label` in `rel-me/Schnaps` until all checks finish. Inspect failures and fix any caused by this change in shared checkout. Run relevant checks, commit and push fixes, and monitor every updated head until all checks pass. Do not merge. Preserve unrelated work. Append fix context and further delegated prompts to this file. Report final head, check results, external blockers. Use bounded waits and meaningful progress updates.

# Follow-up user request

too verbose.. just show Tolerance value abberviated... like Med, Low, High with a tolerance icon

# Delegated monitoring prompt after compact badge update

Monitor PR https://github.com/rel-me/Schnaps/pull/98 after the compact tolerance badge update on branch `codex/gabriel/find-dimensions-tolerance-label`. Wait for all checks on the latest head. Inspect failures and fix any caused by this change, run relevant checks, commit and push fixes, and monitor every updated head until all checks pass. Do not merge. Preserve unrelated work. Append fix context and additional delegated prompts to this file. Report final head, check results, and blockers. Use bounded waits and meaningful progress updates.
