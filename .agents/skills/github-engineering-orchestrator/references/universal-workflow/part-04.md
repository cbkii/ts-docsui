- dirty-state reporting;
- bounded `gh` and `git` operations;
- exact PR, run, or workflow identity;
- post-write verification;
- a final list of actions completed and blockers remaining.

Do not use a user-run script as an excuse to stop analysing. Prepare it only for operations that genuinely require the user’s authenticated environment, device, signing material, or local files.

---

## 20. Long-running work, waits, and progress

Never let a command, workflow poll, device wait, network request, package operation, or child process run without a stopping condition.

For long-running work:

- record the PID, workflow run ID, job ID, or operation identity;
- use bounded polling and total deadlines;
- provide concise progress at meaningful stage boundaries;
- continue independent work while a workflow runs;
- do not restart a healthy run;
- do not dispatch duplicates;
- retry transient failures with bounded backoff;
- stop retrying when the same deterministic failure recurs;
- preserve the last useful logs and artefacts.

Do not tell the user to wait for future work. Perform the work available in the current turn.

Do not flood the conversation with every low-level command. Report decisions, material findings, completed batches, and real blockers.

---

## 21. Genuine stop boundaries

Complete all other useful work before stopping.

A stop is justified when one of these is genuinely required and unavailable:

- repository access or authentication;
- user approval required by branch protection;
- signing key, secret, certificate, or store credential;
- destructive or irreversible decision not already authorised;
- conflicting explicit human requirements;
- physical-device or external-platform validation that cannot be simulated;
- third-party service approval or account ownership;
- ambiguous target identity that could affect the wrong repository;
- a platform limitation that prevents the required write.

When stopped, report:

- exact work completed;
- exact branch and head SHA;
- validations completed;
- exact blocker;
- why proceeding would be unsafe or misleading;
- the smallest command, approval, script, artefact, or decision needed;
- the dependency-ordered work that remains.

Do not use a stop boundary merely because the task is large or inconvenient.

---

## 22. Completion gates and status vocabulary

Use precise status terms.

### Analysed

The relevant state and likely cause were inspected, but no implementation is implied.

### Implemented locally

Code changed in a local worktree. It is not yet pushed or remotely validated.

### Pushed

The intended commit exists on the remote branch and the remote SHA was verified.

### PR-ready

The branch is pushed, the PR accurately describes the current head, and local validation is complete. Remote review or CI may still remain.

### Merge-ready

All valid review feedback is addressed, required checks are green on the current head, the PR is conflict-free, and no known blocker remains.

### Merged

The PR was merged and the resulting default-branch commit was verified.

### Code release-ready

The code and release artefact pass the available qualification, but external or physical acceptance may remain.

### Fully release-ready

All repository, artefact, approval, and required external or physical validation gates are satisfied.

### Released

The intended tag and release exist, assets and hashes were verified, and post-release checks completed.

Never collapse these states into a vague “done”.

---

## 23. Final completion checklist

Do not declare the task complete until all applicable items are true:

- [ ] The exact repository, branch, PR, issue, and head SHA were verified.
- [ ] Repository instructions were read and followed.
- [ ] The root cause and intended behaviour are understood.
- [ ] Scope is complete without unrelated changes.
- [ ] Required implementation is present.
- [ ] Tests prove the changed behaviour and important failure paths.
- [ ] The exact packaged or generated artefact was validated where applicable.
- [ ] Formatting, lint, type, build, and test checks are complete.
- [ ] Canonical GitHub Actions checks are green on the current head.
- [ ] All valid review comments and requested changes are addressed.
- [ ] Non-code review items have replies and classifications.
- [ ] Genuinely resolved threads are resolved.
- [ ] The PR description and checklist match the current head.
- [ ] No temporary files, diagnostic workflows, local data, or secrets remain.
- [ ] The final diff was reviewed for scope creep.
- [ ] The PR is merged when merge was requested.
- [ ] The default branch was re-read and validated after merge.
- [ ] Issues were closed, retained, or updated according to actual acceptance state.
- [ ] Dependent PRs were refreshed after foundational merges.
- [ ] The release was created and verified when release was requested.
- [ ] Remaining limitations are real, explicit, and not disguised unfinished work.
- [ ] Connector health was proven for the exact repository and required operation when connector state mattered.
- [ ] Every active work item has the correct worktree, branch, and head SHA.
- [ ] Multi-issue or multi-PR scope was fully honoured and mapped rather than forced onto one work item.
- [ ] Apparent ownership or concurrency was assessed using meaningful activity within the last 30 minutes.
- [ ] A durable handoff exists for long or resumable work.
- [ ] A cross-file impact map covers material producers, consumers, packaging, workflows, and lifecycle boundaries.
- [ ] Significant changes received a deliberate fresh-context review.
- [ ] Review passes were bounded and duplicate findings were consolidated.
- [ ] Final decisions rely on current GitHub state rather than cached UI summaries.
- [ ] Agent mentions were checked to avoid accidental task triggers.
- [ ] Expensive evidence is bound to exact SHAs, hashes, runs, and environments.
- [ ] High-risk changes include a plain-English risk brief and explicit acceptance where required.

---

## 24. Required final report

At the end of repository work, provide a concise but complete report with:

### Final state

- repository;
- default branch;
- final branch or PR;
- final head SHA;
- merge or release state.

### Work completed

Group changes by coherent area rather than listing every edit.

### Root causes resolved

Explain why the defects occurred and how the implementation prevents recurrence.

### Validation

List exact commands, checks, workflow runs, artefact hashes, device tests, or simulations, and distinguish passed, warned, skipped, and unavailable items.

### GitHub state

Report PRs merged or closed, issues closed or retained, comments or review threads handled, branches cleaned, and remaining automation state.

### Remaining boundaries

List only genuine external, human, signing, approval, physical-validation, or third-party constraints.

Include exact links, run IDs, commit SHAs, tags, release URLs, and artefact hashes where available.

Do not substitute a plan for this report when the requested task was implementation.

---

## 26. Recency-aware multi-agent ownership and coordination

Concurrent work requires awareness and coordination, but stale ownership must not prevent authorised work from progressing.

For each apparent owner, agent, claim, lease, worktree, branch, workflow, or task, inspect:

- latest meaningful commit or push;
- latest comment, review, task update, or heartbeat;
- active workflow or process state;
- lease expiry or lock metadata;
- changed paths and overlap with the requested scope;
- whether the work is still moving toward the same completion objective.

Treat ownership as active only when supported by current evidence. Unless a repository contract defines a different threshold, no meaningful activity for more than **30 minutes** means the ownership or concurrency indication is stale and must not by itself block taking ownership or continuing the work.

Meaningful activity includes a new commit, push, review, comment, heartbeat, lock refresh, running job that is still producing progress, or another verifiable state transition. A static label, old branch, abandoned worktree, stale lock file, or historical assignment is not sufficient.

When activity is recent:

- avoid competing writes to the same branch or files;
- coordinate scopes where practical;
- preserve valid in-progress work;
- use separate worktrees and branches for independent changes;
- identify an integration owner and sequence.

When activity is stale:

- refresh the remote and local state;
- inspect and preserve useful changes;
- take ownership as needed to fulfil the authorised objective;
- record that the prior ownership evidence was stale;
- remove or supersede stale locks, claims, or branches only when safe and authorised.

Do not interpret concurrency rules so strictly that they prevent the requested work, leave a repository abandoned, or require unnecessary user intervention.

---

## 27. Durable session handoff and context recovery

For long, multi-batch, interrupted, compacted, or cross-session work, maintain a durable handoff record.

Include:

- completion objective and non-goals;
- repository and all in-scope items;
- canonical worktree paths, branches, and SHAs;
- decisions already settled;
- completed batches, commits, PRs, and GitHub writes;
- current defect, active command, workflow run, or blocking state;
- exact validation already run and the evidence key to which it applies;
- active ownership or concurrency state and latest meaningful activity;
- next executable step;
- actions that must not be repeated;
- final completion gate.

Keep the handoff outside tracked source unless it is intentionally part of repository documentation. Use an ignored project path or another durable workspace location.

After context compaction, session restart, model handoff, or a request to resume:

1. read the durable handoff;
2. re-read repository instructions;
3. refresh local and remote Git state;
4. refresh PR, issue, review, and workflow state;
5. verify that recorded SHAs and run IDs remain current;
6. update the ledger;
7. continue from the next executable step without repeating completed work.

The handoff is a recovery aid, not authority. Live repository state overrides stale handoff content.

---

## 28. Cross-file impact mapping

Before implementing or finally reviewing a contract-affecting change, create a concise impact map.

Identify:

