---
name: github-engineering-orchestrator
description: Comprehensive GitHub architecture, engineering, development, debugging, pull-request, CI, release, connector-health, repository-orchestration, and authenticated Termux-bridge workflow. Use for focused or multi-issue/PR repository work, complete PR hardening, GitHub Actions failures, release qualification, connector problems, multi-agent coordination, or end-to-end completion through merge and release.
---

# GitHub Engineering Orchestrator

Use this single skill as the universal entry point for GitHub repository work.

It combines:

- GitHub connector health and capability diagnosis;
- pull-request hardening and review-feedback resolution;
- GitHub Actions and CI debugging;
- release engineering and artefact qualification;
- multi-issue, multi-PR, and repository-wide orchestration;
- authenticated Termux or workstation execution bridges;
- the complete universal GitHub workflow instructions;
- reliable Bash and Python execution standards for bridge scripts.

Repository-local instructions, the user’s current request, and live GitHub policy remain authoritative.

## Primary objective

Do not stop at analysis, a plan, a local patch, PR creation, or workflow dispatch when the user authorised a later completion gate.

Progress through the applicable state:

1. analysed;
2. implemented locally;
3. pushed;
4. PR-ready;
5. merge-ready;
6. merged;
7. code release-ready;
8. fully release-ready;
9. released.

State the exact achieved level. Never call unfinished work “done”.

## Load the relevant references

Always read:

- `references/universal-workflow.md`

Then load every specialist reference that matches the task:

| Task | Reference |
|---|---|
| GitHub says connected but access fails, identity or permissions are unclear, or capabilities differ by surface | `references/connector-health.md` |
| Review, harden, finalise, or make a PR merge-ready | `references/pr-hardening.md` |
| Diagnose failed, flaky, skipped, cancelled, warning, or suspicious GitHub Actions checks | `references/ci-debugging.md` |
| Prepare, qualify, publish, promote, or repair a release | `references/release-engineering.md` |
| Work across multiple issues, PRs, branches, workflows, or an entire repository | `references/repository-orchestration.md` |
| Use the user’s authenticated Termux or workstation because the current environment lacks a needed capability | `references/termux-bridge.md` |
| Write or review a Bash execution bridge | `references/bash-script-reliability.md` |
| Write or review a Python execution bridge for Android Termux | `references/python-termux-reliability.md` |

Load multiple references when the task spans multiple workflows. Do not force a broad request into one specialist category.

## Operating sequence

### 1. Resolve exact identity and authority

Before substantive work, resolve:

- owner/repository;
- visibility;
- default branch;
- every in-scope issue, PR, branch, workflow, tag, or release;
- current worktree paths;
- local, remote, base, and PR-head SHAs;
- authentication identity;
- repository-local instructions;
- branch protection and required checks;
- available connector, `git`, `gh`, MCP, device, and local-shell capabilities.

Never rely on repository state remembered from an earlier turn when live state is available.

### 2. Honour focused and multi-item scope

For a focused task, default to one canonical physical worktree and branch.

When the user asks for multiple issues, PRs, branches, or dependent workstreams:

- honour the complete request;
- map every work item;
- use separate worktrees/branches where independent mutable state requires them;
- process and integrate in dependency order;
- do not silently stop after the first item;
- do not combine unrelated work merely to preserve a one-branch default.

Maintain:

| Work item | Worktree | Branch | Head SHA | Owned paths | Dependency | Latest activity | State |
|---|---|---|---|---|---|---|---|

### 3. Assess concurrency using current evidence

Inspect commits, pushes, comments, reviews, workflows, heartbeats, leases, locks, and overlapping paths.

Unless repository policy defines another threshold, an ownership indication with no meaningful activity for more than **30 minutes** is stale and must not by itself block taking ownership or continuing authorised work.

Recent activity requires coordination. Stale labels, branches, assignments, worktrees, or lock files do not create indefinite ownership.

Preserve useful work before taking over.

### 4. Inspect before mutation

Determine:

- intended behaviour;
- root cause;
- affected contracts and invariants;
- producers, consumers, callers, and competing writers;
- tests and fixtures;
- packaging and runtime entrypoints;
- workflows and release paths;
- migration, restart, cache, process, or reboot boundaries;
- compatibility and rollback requirements.

Preserve useful evidence before cleanup or migration.

### 5. Execute in bounded batches

For each batch:

1. refresh local and remote state;
2. state the batch purpose and completion condition;
3. implement the smallest coherent change;
4. add focused regression tests;
5. run narrow validation;
6. run broader validation when warranted;
7. inspect the complete diff;
8. commit and push;
9. verify the remote SHA and PR head;
10. re-read checks, comments, reviews, and workflow state;
11. update the durable handoff and completion ledger;
12. continue to the next dependency-ordered batch.

### 6. Validate the real deliverable

Do not rely only on source-tree checks when packaging, installation, dispatch, runtime, or release behaviour can differ.

Where applicable:

- build the exact artefact;
- inspect its inventory, paths, modes, metadata, and embedded version;
- extract or install it into a fresh environment;
- execute real entrypoints;
- test fresh install and upgrade;
- test rerun/idempotence;
- test failure and rollback;
- bind evidence to source SHA, workflow SHA, environment, and artefact hash.

### 7. Use bounded independent review

For substantial changes, deliberately separate planning, implementation, and fresh-context review.

Use targeted passes:

1. correctness and completeness;
2. cross-file, lifecycle, compatibility, and integration;
3. tests, failure handling, security, and operations;
4. packaging, release, or physical/runtime qualification where relevant.

Give findings stable IDs and deduplicate them.

Stop after two successive passes yield no new confirmed material findings, or after five passes unless substantial new code reopens scope.

### 8. Treat GitHub state as authoritative

UI badges, cached connector summaries, dropdowns, and app-level displays are navigation aids.

Before consequential decisions, query current GitHub state for:

- identity;
- current head SHA;
- review decision;
- complete comments and threads;
- required checks and workflow runs;
- attempts and event type;
- mergeability and branch protection;
- tags, releases, and assets.

Do not retry an ambiguous write until verifying whether it already succeeded.

Treat `@codex`, `@copilot`, and similar mentions as possible executable triggers. Remove accidental mentions and verify task creation before retrying.

### 9. Use a safe execution bridge when required

When the current environment lacks authentication, a checkout, `gh`, signing material, device access, or another required capability:

- complete all available analysis first;
- generate the smallest necessary bridge;
- use the Bash or Python reliability reference;
- verify repository identity, branch, head, authentication, and preconditions;
- bound waits, subprocesses, polling, and retries;
- preserve logs;
- make reruns safe;
- verify every remote write;
- produce a final success/warning/failure summary.

Preparing a script does not mean it ran.

### 10. Explain high-risk work plainly

For security, authentication, authorisation, secrets, destructive operations, migrations, signing, release infrastructure, user data, boot/runtime behaviour, public compatibility, billing, or irreversible external state, provide:

- what is changing;
- what could go wrong;
- who or what is affected;
- why the risk exists;
- protections and tests;
- rollback or recovery;
- the smallest decision or approval required.

Use plain English suitable for a basic user. Define unavoidable technical terms.

## Durable handoff

For long, resumable, compacted, or cross-session work, record:

- objective and non-goals;
- repository and all work items;
- worktrees, branches, and SHAs;
- settled decisions;
- completed commits, PRs, and writes;
- validation and evidence keys;
- active runs and ownership state;
- current defect or blocker;
- next executable step;
- actions not to repeat;
- final completion gate.

On resume, refresh live state before continuing. Live GitHub state overrides stale handoff content.

## Final report

Report:

- repository and default branch;
- each final branch, PR, issue, and SHA;
- root causes and coherent changes;
- exact validation and workflow evidence;
- review threads and feedback handling;
- merge and release state;
- artefact hashes where relevant;
- genuine external boundaries only.

Do not substitute another plan when implementation was requested.
