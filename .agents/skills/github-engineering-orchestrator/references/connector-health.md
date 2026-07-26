# GitHub Connector Health

Establish whether the exact GitHub repository and required operation are available before changing repository state.

## Required inputs

Obtain or resolve:

- repository owner/name;
- repository visibility;
- required operation: read, review, comment, branch, workflow logs, merge, release, or another write;
- active ChatGPT surface;
- expected GitHub identity.

## Workflow

1. Verify the exact repository identity.
2. Inspect the tools available in the active surface. Do not assume another ChatGPT, Codex, CLI, IDE, or mobile surface has the same capabilities.
3. Verify the authenticated GitHub identity where exposed.
4. Confirm the GitHub App or integration is installed for the repository owner or organisation.
5. Prove repository access by reading one known file from the exact repository.
6. Prove each task-critical capability separately:
   - private repository read;
   - PR metadata and diff;
   - comments and reviews;
   - checks and workflow logs;
   - issue or PR write;
   - branch, merge, release, or workflow action.
7. Check OpenAI and GitHub service status when the failure could be platform-wide.
8. Compare with authenticated `gh` or local `git` when available.
9. Classify the failure:
   - unavailable connector;
   - unauthorised repository;
   - wrong identity or workspace binding;
   - missing organisation installation;
   - sync or indexing delay;
   - absent surface capability;
   - individual tool failure;
   - service incident;
   - repository policy denial.
10. Use the least-invasive recovery:
    - refresh current state;
    - switch to a capable surface;
    - use connector for structured reads and `gh`/`git` for gaps;
    - prepare an authenticated user-run bridge only when necessary.
11. Verify recovery with the original failed operation.

## Guardrails

- A **Connected** badge is not proof of repository access.
- Do not repeatedly reconnect or reauthorise without verifying the previous result.
- Do not claim a repository write occurred because a command was prepared.
- Do not expose tokens, cookies, headers, or secret-bearing environment output.
- Do not modify repository state while repository identity is uncertain.

## Required output

Report:

- repository and expected identity;
- capabilities proven;
- exact failure classification;
- evidence and timestamp;
- selected fallback or correction;
- remaining access boundary, if any.
