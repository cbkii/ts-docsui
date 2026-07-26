# Bash Script Reliability and “Just Run” Engineering Standard

## 1. Objective

A reliable Bash script must:

- run from beginning to end under normal and reasonably degraded conditions;
- distinguish genuine fatal failures from warnings, expected negative results and unavailable optional features;
- never stop merely because a harmless command returned non-zero;
- never hide a failure that invalidates the script’s core result;
- never wait forever for input, a network response, a device, a lock or a child process;
- leave temporary files, mounts, locks and child processes in a known state;
- produce enough progress and summary information to explain what happened;
- be safe to run again after success, interruption or partial failure.

“Just run” does not mean ignoring errors. It means every foreseeable result has an intentional, deterministic policy.

---

## 2. Define the execution contract first

Before implementing commands, define:

1. The script’s essential outcome.
2. Which operations are required for that outcome.
3. Which operations are optional enhancements.
4. Which failures are recoverable.
5. Which operations may block or take an unpredictable amount of time.
6. What constitutes overall success.

Every external command must belong to one of these classes:

### A. Expected condition

A non-zero status is part of normal control flow.

Examples:

- `grep` finds no match;
- a file does not yet exist;
- a process is not running;
- an optional property is unavailable.

Handle it with `if`, `case`, `while`, `until`, `&&` or `||`. Do not report it as an error.

### B. Optional operation

Failure does not invalidate the core result.

Policy:

- record a warning;
- use a fallback where available;
- continue;
- include the warning in the final summary.

### C. Retryable operation

Failure may be temporary.

Examples:

- network requests;
- temporarily busy files;
- delayed device availability.

Policy:

- retry only a bounded number of times;
- use a delay or backoff;
- log each attempt;
- preserve the last useful error;
- continue or fail according to the operation’s importance.

### D. Required operation

Failure makes the requested result incomplete, incorrect or unsafe.

Policy:

- print a precise error;
- perform cleanup;
- stop at a controlled boundary;
- return a documented non-zero status.

### E. Unsafe-to-continue condition

Continuing could modify the wrong target, destroy data or produce a misleading result.

Policy:

- print `STOP:` and the exact reason;
- do not attempt speculative recovery;
- clean up and exit non-zero.

Do not allow the shell’s global options to make these decisions implicitly.

---

## 3. Use the correct interpreter explicitly

Use Bash syntax only with Bash.

For a controlled Linux platform:

    #!/bin/bash

For environments where Bash has a variable installation path, such as Termux:

    #!/usr/bin/env bash

Do not:

- use Bash arrays, `[[ ]]`, process substitution or `mapfile` under `#!/bin/sh`;
- place several flags in the shebang and assume every operating system parses them identically;
- depend on the user launching the script from a particular directory;
- assume the user’s interactive aliases or shell startup files will be loaded.

Determine the script directory when resources are stored beside the script:

    SCRIPT_DIR=$(
        cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 &&
        pwd -P
    ) || {
        printf 'ERROR: Cannot determine script directory.\n' >&2
        exit 1
    }

Use absolute or script-relative paths after that point.

---

## 4. Do not apply “strict mode” blindly

The common line:

    set -euo pipefail

is not a complete reliability strategy. It can introduce sudden exits, context-dependent behaviour and false failures.

### 4.1 `set -e` / `errexit`

Do not enable `set -e` by default in collection, diagnostic, recovery, migration or best-effort scripts.

`set -e` has exceptions involving:

- `if` and `while` conditions;
- `&&` and `||` lists;
- negated commands;
- pipelines;
- functions called from conditional contexts;
- command substitutions and subshells.

The same command can therefore be fatal in one location and ignored in another.

It also treats any non-zero command status as a possible reason to terminate, even where non-zero is meaningful rather than exceptional.

Examples of surprising failures include:

    ((count++))

The arithmetic command returns status 1 when its expression evaluates to zero. With `set -e`, the first increment may terminate the script.

Safer:

    ((count += 1))

or:

    count=$((count + 1))

Use explicit handling:

    command_output=$(some_command)
    rc=$?

    if ((rc != 0)); then
        warn "some_command failed with status ${rc}; continuing with fallback"
        command_output='fallback'
    fi

For a required command:

    if ! required_command; then
        fatal "required_command failed; the requested result cannot be completed"
    fi

Do not use `set -e` as a substitute for reviewing command exit statuses.

### 4.2 `set -u` / `nounset`

`set -u` causes an unset-variable expansion to terminate a non-interactive shell.

This can be useful in small, fully controlled scripts, but it is hazardous where:

- environment variables are optional;
- arrays may be empty;
- cleanup runs after partial initialisation;
- configuration is loaded conditionally;
- positional parameters may be absent.

Prefer explicit defaults and validation:

    output_dir=${OUTPUT_DIR:-"$HOME/output"}
    optional_value=${OPTIONAL_VALUE:-}

    if [[ -z ${required_value:-} ]]; then
        fatal "required_value is not configured"
    fi

Cleanup code must always tolerate variables that were never initialised:

    [[ -n ${tmp_dir:-} ]] && rm -rf -- "$tmp_dir"

Enable `set -u` only after auditing every expansion and every interruption path.

### 4.3 `set -o pipefail`

Without `pipefail`, a pipeline normally reports the status of its final command. With `pipefail`, a non-zero status from an earlier command can fail the pipeline.

This is useful only when failure of any pipeline component invalidates the result.

It can also create false failures where a consumer intentionally stops early, for example:

    producer | head -n 1
    producer | grep -q pattern

The producer may receive a broken-pipe signal after the consumer has already obtained the required result.

Rules:

- enable `pipefail` only after auditing every pipeline;
