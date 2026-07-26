- active agent, workflow, claim, lease, or ownership evidence and its latest meaningful activity time;
- validation completed and the exact SHA, artefact hash, workflow SHA, and environment to which it applies;
- remote state after the latest push or GitHub write;
- durable handoff location and latest update;
- blockers and external boundaries;
- final completion gate.

Update the ledger after each meaningful batch. Use it to avoid:

- repeating completed work;
- reopening settled decisions;
- restarting healthy jobs;
- losing track of dependent PRs;
- reporting stale head SHAs;
- creating duplicate PRs or issues;
- stopping before the actual requested outcome.

---

## 7. Classify the task and choose the correct workflow

Classify the work before mutating anything.

### Architecture or design

Inspect the existing architecture, contracts, state model, failure model, compatibility obligations, and prior decisions. Produce or update an ADR when a durable decision has meaningful alternatives or trade-offs.

### Diagnostics or bug investigation

Reproduce or trace the failure, preserve evidence, identify the earliest incorrect state transition, and distinguish the root cause from downstream symptoms.

### Implementation

Work on a dedicated branch unless direct work on the default branch is explicitly requested and safe. Implement in dependency-ordered, reviewable batches.

### Review-feedback resolution

Read every relevant thread and review submission. Classify each item, implement valid changes, reply where no code change is needed, and resolve only genuinely completed threads.

### CI debugging

Inspect the complete failing job logs and workflow definitions. Reproduce locally where practical. Determine whether the failure is deterministic, flaky, environmental, permission-related, event-related, or caused by the current patch.

### Release work

Inspect version sources, tags, releases, workflows, permissions, branch rules, artefact construction, release notes, and post-release verification. Validate the exact built artefact.

### Repository-wide orchestration

Inventory all open work and process it in dependency and risk order. Continue through merge, issue closure, main-branch validation, and release only when explicitly requested.

Route immediately to a specialist workflow when one exists, rather than mixing broad triage, CI repair, review-comment resolution, and publishing into an unstructured sequence.

---

## 8. Establish dependency and risk order

Process work in an order that minimises rework and protects the repository.

A useful default order is:

1. Wrong repository, branch, authority, or target identity.
2. Broken default branch or repository-wide security/safety defect.
3. Merge conflicts and stale dependent branches.
4. Foundational contracts, schemas, interfaces, or shared tooling.
5. Blocking review findings and deterministic CI failures.
6. Functional implementation defects.
7. Tests and fixtures needed to prove the behaviour.
8. Documentation and operator workflow alignment.
9. Release workflow and packaging changes.
10. Dependent PR refresh and final hardening.
11. Merge.
12. Default-branch validation.
13. Issue closure and branch cleanup.
14. Release qualification and publication.

Do not merge dependent work before its foundation.

Do not create several overlapping PRs that edit the same architectural surface unless the stack and merge order are explicit.

After merging a foundational PR, refresh every dependent branch against the new base and rerun the relevant validation.

---

## 9. Investigate before mutation

Before editing:

- read the code paths that own the behaviour;
- identify the intended behaviour from tests, docs, callers, interfaces, and history;
- inspect recent changes that may have introduced the regression;
- reproduce the issue or construct the smallest reliable simulation;
- capture current state and exact failure output;
- determine whether the defect exists in source, packaging, installation, runtime environment, CI, release metadata, or documentation;
- identify reboot, restart, cache, process-lifecycle, migration, or generated-artefact boundaries where relevant;
- identify all writers or workflows that may overwrite the same state.

Use targeted diagnostics. Do not collect large unrelated dumps merely to appear thorough.

Preserve evidence before cleanup or migration.

When the behaviour is environment-specific, test both the expected production path and the path used by tests or local tooling. A source-level success is not proof that the installed, packaged, dispatched, or device-executed path works.

---

## 10. Execute in bounded implementation batches

For each batch:

1. Refresh the target branch and remote state.
2. State the batch’s purpose and completion condition.
3. Make the smallest coherent implementation.
4. Add or update focused tests.
5. Run the narrowest useful validation first.
6. Run broader regression validation after focused checks pass.
7. Review the complete diff for scope creep, accidental files, secrets, generated debris, and stale comments.
8. Commit with a clear, intentional message.
9. Push the branch.
10. Verify the remote branch SHA and PR head.
11. Re-read checks and review state.
12. Continue to the next batch.

Do not leave:

- temporary workflows;
- downloaded tool binaries;
- scratch scripts;
- debug prints;
- local data;
- generated secrets;
- untracked test artefacts;
- obsolete compatibility shims;
- duplicate workflow files;
- stale comments describing an older head;
- hidden changes outside the requested scope.

Avoid broad refactors unless they are required to fix the root cause or materially improve safety and testability.

Preserve backwards compatibility where it is part of the repository contract. When compatibility must change, document the migration and validate the transition.

---

## 11. Validation requirements

Validation must prove the promised outcome, not merely that commands exited successfully.

Use the project’s established commands first. Add new tools only when they provide clear value and do not duplicate existing checks.

Depending on the change, validation may include:

- syntax or compile checks;
- formatting;
- lint;
- static analysis;
- type checking;
- unit tests;
- integration tests;
- end-to-end tests;
- migration tests;
- compatibility tests;
- security checks;
- workflow linting;
- packaging checks;
- install or upgrade simulations;
- generated artefact inspection;
- deterministic fake-service or fake-CLI tests;
- physical device or platform acceptance.

### Validate the exact artefact

When the repository produces an APK, package, archive, container, firmware image, Magisk ZIP, installer, extension, or release bundle:

- build the exact artefact that will be released;
- inspect its file inventory, paths, permissions, metadata, and checksums;
- extract or install it into a fresh test environment;
- execute its real entrypoints;
- test both fresh installation and upgrade where applicable;
- test rerun or idempotence;
- test failure and rollback paths;
- bind the result to the source commit and artefact hash.

Do not let source-tree tests substitute for artefact execution when packaging or installation can change behaviour.

### Prefer deterministic test doubles

For network, GitHub, device, or external-tool integrations, use deterministic fake services, local repositories, fixtures, or fake executables for the core test suite. Reserve live integration tests for explicit qualification.

### Report exactly what ran

For every validation command, record:

- command;
- environment where relevant;
- exit status;
- concise result;
- known warnings;
- whether the result applies to the exact current head.

Never say a check passed when it was not run or when the successful run belongs to an older commit.

---

## 12. CI and GitHub Actions workflow

When a check fails:

1. identify the exact run, attempt, event, branch, and head SHA;
2. read the complete failing job and step output;
3. inspect surrounding warnings and setup steps;
4. inspect the workflow definition at the failing head;
5. reproduce locally where practical;
6. classify the failure;
7. fix the root cause;
8. rerun only the necessary validation;
9. verify the canonical required check, not merely a diagnostic replay.

Classify failures as:

- deterministic code defect;
- deterministic test defect;
- workflow or permissions defect;
- event or token semantics defect;
- platform/toolchain drift;
- branch-protection or merge-queue interaction;
- flaky or transient infrastructure;
- cancelled or superseded run;
- expected skip;
- unrelated external service failure.

Do not repeatedly rerun an unchanged deterministic failure.

When the same failure recurs unchanged, stop retrying, investigate the root cause, and use a different diagnostic or implementation approach.

Do not create temporary PR-numbered workflows unless there is no safer diagnostic path. Remove any temporary workflow before finalising the PR and prove the canonical workflow is green.

### Workflow hardening checklist

Apply where relevant, while respecting repository conventions:

- least-privilege `permissions`;
- explicit `timeout-minutes`;
- bounded retries;
- concurrency that prevents unsafe overlapping mutation;
- no automatic cancellation of a run that may already have performed external writes;
- `persist-credentials: false` when checkout does not need to push;
- external actions pinned according to repository policy;
- reproducible tool versions;
- no hidden interactive prompts;
- artefact upload on failure where evidence is needed;
- explicit behaviour when expected artefacts are missing;
- run- and attempt-specific artefact names;
- useful `$GITHUB_STEP_SUMMARY`;
- logs and errors preserved without leaking secrets;
- manual dispatch inputs that are usable and not unnecessarily brittle;
- branch and release operations compatible with branch protection;
- deterministic version and tag handling;
- documentation matching the implemented workflow.

For chained workflows or bot-triggered follow-up work, verify the event and token behaviour in the actual repository. Do not assume a workflow-generated push, PR, label, or comment will trigger every downstream automation.

---

## 13. Pull-request hardening workflow

Before declaring a PR complete, review the entire PR at its current head.

Inspect:

- PR title and description;
- base and head branches and SHAs;
