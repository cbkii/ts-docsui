# GitHub Termux Bridge

Use the user’s authenticated environment only for operations that genuinely cannot be completed through the connected GitHub tools.

## First complete available work

Before writing a bridge:

- inspect all accessible repository state;
- determine the exact remaining operation;
- avoid transferring analysis or decisions the assistant can complete directly;
- identify the minimum output needed to continue.

## Script requirements

Use Bash for command orchestration unless complexity requires Python.

The script must:

- use the correct interpreter;
- avoid mechanical `set -euo pipefail`;
- classify expected, optional, retryable, required, and unsafe outcomes;
- verify `gh auth status`;
- use explicit `owner/repo`;
- resolve the canonical repository root;
- report worktrees, branch, upstream, dirty state, and local/remote SHA;
- reject the wrong repository, branch, or head;
- preserve unrelated user changes;
- bound `git`, `gh`, network, polling, and workflow waits;
- avoid hidden prompts;
- use arrays and correctly quoted arguments;
- avoid `eval`;
- use secure temporary files;
- preserve logs and command exit status;
- clean only resources it owns;
- be safe to rerun after success, interruption, or ambiguous writes;
- verify every remote write by re-reading GitHub state;
- avoid exposing tokens, headers, keys, or signed URLs;
- print meaningful stages and a final result summary.

## Multi-item work

When the user requested several issues or PRs:

- honour all items;
- map each to its intended worktree and branch;
- process in dependency order;
- do not combine unrelated changes merely for convenience;
- do not stop after the first successful item.

## Concurrency

Inspect latest commits, pushes, runs, comments, and locks. Ownership with no meaningful activity for over 30 minutes is stale unless repository policy specifies otherwise. Preserve useful changes, but do not let stale state block authorised work.

## GitHub operations

Before writes, print the exact target and intended effect. After writes:

- query the issue, PR, branch, workflow, release, or tag;
- verify the expected state;
- record IDs, URLs, SHAs, and hashes;
- do not retry an ambiguous write until verification.

## Deliverables

Provide:

- a directly runnable script;
- required invocation;
- expected output or archive path;
- exact data the user should return;
- no unnecessary manual reconstruction steps.

A prepared script is not proof that the operation ran. Report execution state accurately.
