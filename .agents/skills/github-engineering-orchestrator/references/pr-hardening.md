# GitHub PR Hardening

Complete a pull request against its exact current head. Do not rely on cached UI summaries or truncated previews.

## Context preflight

Resolve and record:

- owner/repository and PR number;
- base and head branches and SHAs;
- canonical worktree path and local branch when editing;
- applicable repository instructions;
- merge method and required checks;
- current reviews, comments, threads, and check state.

Verify the worktree before every edit, commit, push, rebase, or merge.

## Complete inspection

Inspect:

- title, body, checklist, commits, changed files, and full diff;
- unresolved and relevant resolved review threads;
- all review submissions, including requested changes;
- inline and top-level comments;
- bot, linter, security, dependency, and quality feedback;
- failed, warning, skipped, cancelled, flaky, or suspicious checks;
- linked logs, artefacts, screenshots, and generated reports;
- merge conflicts and branch protection;
- current GitHub state rather than app-only summaries.

## Cross-file impact map

For each changed contract or state, identify producers, consumers, callers, tests, configuration, migrations, generated files, packaging, workflows, runtime entrypoints, documentation, lifecycle boundaries, and competing writers. Review relevant files outside the diff.

## Finding classification

Assign stable IDs. For each finding record:

- severity and confidence;
- affected file/location;
- violated contract or observable failure;
- evidence or reproduction;
- required code, test, documentation, or non-code response;
- classification: valid, already fixed, stale, duplicate, false positive, out of scope, or human/external boundary.

## Implementation and validation

1. Implement valid fixes in coherent batches.
2. Add focused tests that would fail without the fix.
3. Run narrow validation, then broader regression checks.
4. Build and test the exact artefact when packaging can alter behaviour.
5. Commit, push, and verify the remote PR head SHA.
6. Re-read canonical checks and reviews on the new head.
7. Reply where no code change is needed.
8. Resolve only genuinely completed threads.
9. Update the PR body and checklist to describe the current head.
10. Remove temporary workflows, diagnostics, debug output, and stale references.

## Bounded fresh-context review

Use targeted passes:

1. correctness and completeness;
2. cross-file, lifecycle, compatibility, and integration effects;
3. tests, failure handling, security, and operations;
4. packaging or release qualification when relevant.

Deduplicate findings. Stop after two successive passes yield no new confirmed material findings, or after five passes unless substantial new code reopens scope.

A fresh-context reviewer must verify the specification, current diff, impact map, failure paths, tests, and exact deliverable without accepting the implementer’s conclusions as evidence.

## Agent-trigger hygiene

Treat `@codex`, `@copilot`, and similar mentions as possible task triggers. Remove accidental mentions. Invoke once only when a new task is intentional, then verify the created task or run before retrying.

## Merge-ready gate

Do not declare merge-ready until:

- the current head is verified;
- valid feedback is addressed;
- required checks are green on that head;
- no conflicts or temporary files remain;
- the PR description is current;
- final diff and changed-file inventory are reviewed;
- material external or physical validation is explicitly classified.

## Final output

Report:

- final head SHA;
- fixes made;
- non-code responses;
- stale, duplicate, false-positive, and out-of-scope findings;
- validation commands and results;
- thread and review state;
- merge readiness or exact remaining boundary.
