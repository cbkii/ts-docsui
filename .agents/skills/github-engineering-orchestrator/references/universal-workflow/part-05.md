- the changed contract, invariant, schema, interface, or state;
- producers and writers;
- consumers, callers, and readers;
- tests and fixtures;
- configuration and feature flags;
- migrations and compatibility layers;
- generated files;
- packaging and release logic;
- workflows and automation;
- runtime entrypoints;
- documentation and operator procedures;
- other components that write or cache the same state.

Review relevant related files even when they are not present in the diff.

For each changed contract, answer:

- Who calls or depends on it?
- What parses, serialises, installs, packages, or exposes it?
- What other component can overwrite it?
- What lifecycle, restart, cache, migration, or reboot boundary applies?
- What focused test proves each material consumer remains valid?
- What exact built artefact proves packaging did not change the behaviour?

Do not approve a locally correct change while known callers, packaging paths, workflows, or lifecycle boundaries remain unchecked.

---

## 29. Independent planning, implementation, and review

For substantial or high-risk changes, separate the following roles where practical:

1. **Planner:** defines requirements, architecture, constraints, dependencies, risks, and observable acceptance criteria.
2. **Implementer:** completes bounded, dependency-ordered changes and records evidence.
3. **Fresh-context reviewer:** reviews the specification, current diff, impact map, and validation evidence without relying on the implementer’s unverified conclusions.

The same person or agent may perform more than one role, but the final review must deliberately reset assumptions and re-derive correctness from evidence.

The reviewer must:

- inspect the exact current head;
- challenge hidden assumptions;
- inspect related files outside the diff;
- verify failure and rollback paths;
- verify that tests would fail without the fix;
- verify the real packaged or installed deliverable where relevant;
- classify findings by evidence rather than preference.

After review fixes, run a final current-head verification. Do not treat the implementation session’s confidence as independent review evidence.

---

## 30. Bounded review saturation and finding deduplication

A single AI review may miss material issues, but unlimited review loops waste time and generate duplicates.

Use targeted passes for significant PRs:

1. correctness and completion;
2. cross-file, lifecycle, compatibility, and integration effects;
3. tests, failure handling, security, and operational behaviour;
4. packaging, release, or physical/runtime qualification when relevant.

Assign each finding a stable ID and record:

- severity;
- confidence;
- affected file and location;
- violated contract or observable failure;
- evidence or reproduction path;
- recommended validation;
- current classification and resolution.

Deduplicate repeated findings. Reopen a finding only when new evidence or a new code change materially changes it.

Stop the review loop after two successive passes produce no new confirmed material findings, or after five passes, unless substantial new code reopens the review surface.

Do not spend review capacity on subjective style issues unless requested or repository policy makes them material.

---

## 31. Authoritative GitHub state and agent-trigger hygiene

Treat UI badges, connector summaries, dropdowns, cached review panels, and app-level PR displays as navigation aids rather than final evidence.

For consequential decisions, query current GitHub state directly and compare:

- repository and PR identity;
- current head SHA;
- review decision;
- complete comments and review threads;
- required checks and workflow runs;
- run attempts and event type;
- mergeability and branch protection;
- tag, release, and asset state.

When UI and GitHub disagree, GitHub’s current repository state is authoritative. Record the discrepancy when it affects the task.

Treat `@codex`, `@copilot`, and other agent mentions as potentially executable task triggers.

Before posting any comment or review:

- remove accidental agent mentions from acknowledgements, quotations, and summaries;
- distinguish replying to an existing reviewer from requesting a new agent task;
- use one explicit invocation only when a new task is intended;
- verify whether the task or run was created before retrying;
- record the resulting task, comment, workflow, or run identity;
- do not repeatedly mention an agent merely because a response is delayed.

---

## 32. Specialist skills supplement

Keep this comprehensive document as the authoritative universal project source.

Use small specialist account skills to activate focused workflows without repeatedly loading every detailed section. Specialist skills supplement this document; they do not replace it or override the user’s request, repository instructions, or live GitHub policy.

Recommended skills:

- `github-connector-health`;
- `github-pr-hardening`;
- `github-ci-debugging`;
- `github-release`;
- `github-repo-orchestration`;
- `github-termux-bridge`.

A specialist skill must:

- state precise trigger conditions in its description;
- remain self-contained enough to work outside this project;
- defer to this source when both are available;
- load only the context needed for its workflow;
- preserve the universal identity, safety, evidence, and completion rules;
- avoid creating a second conflicting source of truth;
- be revised when repeated real-world use exposes a gap.

Use one or more skills together when the task genuinely spans their scopes.

---

## 33. SHA-keyed evidence reuse and execution budgets

Bind expensive analysis and validation evidence to the inputs that make it valid.

Record, as applicable:

- source commit SHA;
- base and head SHAs;
- workflow file SHA;
- dependency-lock hash;
- test fixture or configuration hash;
- built artefact hash;
- environment and toolchain version;
- device, platform, or runtime identity;
- workflow run and attempt.

Reuse evidence only while all relevant inputs remain unchanged.

Before rerunning an expensive operation, determine:

- what changed since the prior result;
- whether the changed files invalidate the evidence;
- whether a focused rerun is sufficient;
- whether a canonical full rerun is required before merge or release.

Set bounded budgets for:

- review passes;
- workflow reruns;
- connector reconnect or reauthorisation attempts;
- polling duration;
- transient retries;
- diagnostic branches or temporary workflows.

When a budget is exhausted, do not continue the same unchanged loop. Reassess the root cause and switch approach.

---

## 34. High-risk acceptance and plain-English risk brief

AI review and green CI are evidence, not accountability.

Changes affecting security, authentication, authorisation, secrets, destructive operations, data migrations, signing, release infrastructure, user data, boot or runtime behaviour, public compatibility, billing, or irreversible external state require an explicit human or independently accountable acceptance gate unless the user has already clearly authorised that exact risk.

Before requesting acceptance, provide a plain-English brief suitable for a basic user:

### What is changing?

Describe the change without specialised terminology, or define necessary terms immediately.

### What could go wrong?

Explain the concrete failure, such as loss of data, loss of access, a broken release, an unbootable device, exposure of a secret, unintended charges, or incompatible upgrades.

### Who or what could be affected?

Identify repositories, users, devices, releases, data, credentials, or external services.

### Why is this risk present?

Explain the technical reason in simple language rather than merely labelling the change “high risk”.

### What protections are in place?

Describe backups, dry runs, branch protection, tests, staged rollout, reversible changes, checksums, transaction boundaries, rollback, and monitoring.

### How can it be recovered?

State the exact rollback or recovery path and any limit on reversibility.

### What decision is required?

Ask for the smallest explicit approval or choice needed.

The gate must review the final diff, unresolved uncertainty, failure and rollback evidence, exact artefact, and any production or physical validation requirement.

Do not hide risk behind jargon, raw logs, severity labels, or a generic request to approve.

## 25. Prohibited failure patterns

Do not:

- act on stale repository state;
- assume an old PR head is current;
- rely on truncated previews or aggregate summaries;
- inspect only unresolved comments and ignore requested-change reviews;
- rerun the same deterministic CI failure repeatedly;
- restart healthy workflows;
- create duplicate issues, PRs, comments, or releases;
- retry an ambiguous write before checking whether it succeeded;
- use fuzzy first-result search as authoritative identity;
- weaken safety, tests, branch protection, or release gates merely to obtain green CI;
- add temporary workflows and leave them in the PR;
- commit downloaded binaries, scratch files, logs, credentials, or local data;
- make broad unrelated refactors during a focused repair;
- resolve review threads before the issue is genuinely fixed;
- claim merge-ready with failing or stale checks;
- claim release-ready based only on source tests;
- stop after a plan when implementation was requested;
- stop after opening a PR when merge or release was requested;
- hide a required failure as a warning;
- treat an optional warning as a fatal result without justification;
- confuse code readiness with physical or production validation;
- ask the user to repeat information already available in the repository, conversation, or project sources;
- force a multi-issue or multi-PR request into one branch when separate work items are required;
- treat stale ownership with no meaningful activity for over 30 minutes as an indefinite blocker;
- allow concurrent agents to mutate the same paths without current evidence and coordination;
- rely on UI summaries when direct GitHub state is available;
- accidentally trigger agents through casual `@` mentions;
- repeat expensive reviews or workflow runs when the relevant SHA and evidence remain unchanged;
- request approval for high-risk work without explaining the concrete risk in plain English.

---

## Governing principle

> Refresh exact state, establish authority, find the root cause, implement in dependency order, validate the real deliverable, verify every remote write, and continue until the authorised completion gate is genuinely satisfied.
