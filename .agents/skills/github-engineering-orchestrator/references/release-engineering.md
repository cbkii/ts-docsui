# GitHub Release Engineering

Complete releases from exact repository state and validate the real deliverable.

## Preflight

Resolve:

- owner/repository and visibility;
- exact default-branch head;
- open release-blocking PRs and issues;
- version sources and ordering rules;
- current tags, drafts, prereleases, and published releases;
- release workflow inputs, permissions, and branch protection;
- build and packaging commands;
- artefact manifest, checksums, provenance, update channel, and rollback;
- required physical or external validation.

## Workflow

1. Prove repository quiescence or identify the dependency-ordered work that must land first.
2. Select or calculate the version deterministically.
3. Update every authoritative version source consistently.
4. Run full qualification on the exact release candidate.
5. Build the exact artefact that will be published.
6. Inspect inventory, paths, modes, metadata, and embedded version.
7. Extract or install it into a fresh environment.
8. Test fresh install, upgrade, rerun/idempotence, failure, rollback, and runtime entrypoints where applicable.
9. Bind evidence to source SHA and artefact hash.
10. Generate concise release notes and comparison information.
11. Create or verify the tag and release.
12. Upload and re-read assets; verify names, sizes, URLs, and hashes.
13. Run post-release smoke or installation validation.
14. Report exact tag, release, source SHA, artefacts, and hashes.

## Manual workflow usability

Keep manual dispatch safe but usable. Avoid brittle blank-input behaviour, redundant confirmation strings, unnecessary bootstrap gates, or multiple-device requirements unless they protect a real risk. Prefer explicit modes such as dry-run, prepare, prerelease, promote, publish, or stable.

Do not advertise an update channel that users cannot access.

## High-risk acceptance

For security, signing, destructive migration, release infrastructure, user data, boot/runtime, or public compatibility risk, provide a plain-English brief:

- what is changing;
- what could go wrong;
- who or what is affected;
- why the risk exists;
- protections and tests;
- exact rollback or recovery;
- smallest decision or approval required.

Avoid unexplained jargon. Define necessary technical terms.

## Completion gate

Distinguish:

- code release-ready;
- fully release-ready;
- released.

Do not publish stable solely because prerelease CI succeeded. Verify the stable gates, exact artefact, release assets, and post-release state.
