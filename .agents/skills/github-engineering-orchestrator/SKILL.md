---
name: github-engineering-orchestrator
description: Complete ts-docsui GitHub architecture, implementation, PR, CI and release work through the authorised end state.
---

# TS18 GitHub Engineering Orchestrator

Use this skill as the repository entry point for substantive GitHub work. Repository `AGENTS.md`, the user’s current request and live GitHub policy remain authoritative.

## Completion objective

Progress through the applicable states: analysed, implemented, pushed, PR-ready, merge-ready, merged, code release-ready, fully release-ready and released. State the exact achieved level; never call unfinished work done.

## Operating sequence

1. Resolve `cbkii/ts-docsui`, the default branch, current head SHA, in-scope branch/PR/workflow/tag and available GitHub capabilities.
2. Read `AGENTS.md`, `README.md`, relevant workflow files and all directly affected scripts before mutation.
3. Check for current overlapping commits, PRs, reviews, workflows or ownership evidence. Activity older than 30 minutes does not by itself block authorised work.
4. Identify the root cause and all affected producers, consumers, tests, packaging paths, runtime entrypoints and release contracts.
5. Implement the smallest coherent change on a dedicated branch.
6. Add regression tests that fail without the fix. Run focused checks, then the complete required validation from `AGENTS.md`.
7. For packaging or release work, build and inspect the exact STORE-only Magisk ZIP, checksum, embedded metadata and `update.json`.
8. Push, verify the remote head, create or update the PR, and inspect the full current-head diff, comments, reviews and checks.
9. Continue through the user-authorised completion gate. Do not merge or publish unless expressly authorised.

## Release-specific invariants

- `module/module.prop` is the persistent version authority.
- Provider APK version metadata, ZIP filename/content, checksum, tag and `update.json` must agree.
- New release tags point to the committed version source.
- Existing tags never move; exact-tag rebuilds replace only known release assets.
- Blank manual inputs remain usable and deterministic.
- Release writes are serialized and bounded.
- Physical TS18 acceptance is reported separately from CI evidence.

## PR and CI hardening

Inspect complete logs rather than summaries. Classify deterministic code/test/workflow defects separately from flaky infrastructure, expected skips and external failures. Do not rerun unchanged deterministic failures. Resolve review threads only after the issue is genuinely fixed. Stop independent review after two successive passes find no new confirmed material issue, unless new code reopens scope.

## Final report

Report the repository, branch, PR, final head SHA, coherent changes, exact commands/results, workflow/check state, artefact hash where produced, review handling and any genuine external boundary.
