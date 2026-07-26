# GitHub Repository Orchestration

Honour the complete requested scope across multiple issues, PRs, branches, and workflows.

## Inventory

Refresh:

- repository instructions and architecture;
- every in-scope and open PR and issue;
- base/head SHAs, reviews, comments, checks, and conflicts;
- control issues, claims, leases, locks, and automation branches;
- active workflow runs and artefacts;
- tags, releases, and branch protection;
- local worktrees and branches.

Do not limit discovery to agent-ready or status labels when the request covers all work.

## Work-item map

Maintain:

| Work item | Worktree | Branch | Head SHA | Owned paths | Dependency | Latest activity | State |
|---|---|---|---|---|---|---|---|

Default to one worktree and branch per independently mutable work item. Do not force a multi-PR request onto one branch, and do not stop after the first item.

## Recency-aware ownership

Inspect commits, pushes, comments, reviews, heartbeats, locks, and active runs.

Unless repository policy says otherwise, no meaningful activity for more than 30 minutes means an ownership marker is stale and must not by itself block taking ownership. Preserve useful work, refresh state, record the takeover, and continue.

Recent active work requires coordination and separate paths. Stale labels, branches, or locks do not create indefinite ownership.

## Dependency order

Prefer:

1. identity, authority, and default-branch safety;
2. foundational contracts and shared tooling;
3. conflicts and stale dependants;
4. review and deterministic CI blockers;
5. implementation and regression tests;
6. documentation and operations;
7. packaging and release workflows;
8. dependent PR refresh;
9. merge;
10. default-branch validation;
11. issue closure and branch cleanup;
12. release qualification and publication when requested.

## Execution

For each batch:

- refresh state;
- implement;
- validate;
- review the diff;
- commit and push;
- verify remote state;
- harden the PR;
- merge or close when genuinely complete;
- refresh dependants;
- update the durable handoff and ledger.

Do not restart healthy workflows or retry ambiguous writes before checking whether they succeeded.

## Independent review and evidence

Use cross-file impact maps, bounded review passes, fresh-context review, and SHA-keyed evidence. Query GitHub directly for final state rather than trusting UI summaries.

## Completion

Verify:

- every requested item is merged, closed, retained, or explicitly blocked for a valid reason;
- final comments explain closures or supersession;
- permanent control issues remain open;
- the default branch is current and green;
- dependent branches are refreshed;
- release state matches the request;
- no stale automation or temporary branches remain without explanation.

Provide a final ledger with repository, branches, SHAs, PRs, issues, checks, releases, and genuine remaining boundaries.
