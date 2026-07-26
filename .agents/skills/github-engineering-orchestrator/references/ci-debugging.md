# GitHub CI Debugging

Diagnose the exact failing run and fix the root cause rather than repeatedly rerunning unchanged failures.

## Resolve exact evidence

Record:

- owner/repository;
- branch and head SHA;
- workflow file and its SHA;
- run ID, attempt, event, actor, and job;
- required versus optional check status;
- canonical check name used by branch protection.

Read the complete failing job and step output. Inspect setup steps, warnings, annotations, artefacts, and workflow definitions at the failing head.

## Classify the failure

Use one of:

- deterministic code defect;
- deterministic test defect;
- workflow or permissions defect;
- event, token, fork, or actor semantics;
- platform or toolchain drift;
- branch protection or merge queue interaction;
- flaky or transient infrastructure;
- cancelled or superseded run;
- expected skip;
- unrelated external service failure.

## Investigation

1. Reproduce locally where practical.
2. Compare local, diagnostic, and canonical environments.
3. Inspect changed contracts and related files outside the diff.
4. Verify tool versions, permissions, checkout state, caches, generated inputs, secrets availability, and event payload assumptions.
5. Preserve failure evidence before changing workflows.
6. Do not create a temporary PR-numbered workflow unless no safer diagnostic path exists.

## Repair

- Make the smallest coherent fix.
- Add a regression test or deterministic fixture where possible.
- Use least-privilege permissions.
- Bound workflow duration and retries.
- Preserve useful failure artefacts without exposing secrets.
- Remove temporary diagnostic workflows before finalisation.
- Verify the canonical required check, not only a replay.

## SHA-keyed evidence and budgets

Bind results to the head SHA, workflow SHA, dependency-lock hash, environment, run, and attempt. Reuse evidence only while relevant inputs are unchanged.

Do not rerun an unchanged deterministic failure. Use bounded retry for genuinely transient failures. When the same result recurs, change diagnostic approach.

## Completion gate

Report success only when:

- the root cause is explained;
- the fix exists on the verified remote head;
- focused validation passes;
- the canonical required check is green on that head;
- temporary diagnostics are removed;
- remaining flaky or external behaviour is explicitly evidenced.

## Final output

Include exact run IDs, attempts, SHAs, commands, classification, root cause, fix, validation, and any genuine external boundary.
