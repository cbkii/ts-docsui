- avoid pipelines whose individual statuses need different policies;
- capture `PIPESTATUS` immediately when individual statuses matter;
- do not run another command before copying `PIPESTATUS`.

Example:

    producer | transformer | consumer
    pipeline_status=("${PIPESTATUS[@]}")

    if ((pipeline_status[0] != 0)); then
        warn "producer failed with status ${pipeline_status[0]}"
    fi

    if ((pipeline_status[1] != 0)); then
        warn "transformer failed with status ${pipeline_status[1]}"
    fi

    if ((pipeline_status[2] != 0)); then
        fatal "consumer failed with status ${pipeline_status[2]}"
    fi

### 4.4 Recommended default

For reliability-oriented scripts, begin without global automatic-exit behaviour:

    #!/usr/bin/env bash

Then handle failures explicitly.

Options may be enabled in a small, audited scope:

    (
        set -o pipefail
        required_producer | required_consumer
    )
    rc=$?

    if ((rc != 0)); then
        fatal "Required pipeline failed with status ${rc}"
    fi

---

## 5. Check outcomes, not assumptions

Use the command’s exit status as the primary result.

Preferred:

    if mkdir -p -- "$output_dir"; then
        log "Output directory is ready: $output_dir"
    else
        fatal "Cannot create or access output directory: $output_dir"
    fi

Avoid redundant check-then-act patterns:

    if [[ ! -d $output_dir ]]; then
        mkdir "$output_dir"
    fi

The state can change between the check and the action, and `mkdir -p` already expresses the intended idempotent operation.

Check prerequisites once at an appropriate boundary. Do not repeatedly check the same fact before every command unless it can legitimately change during execution.

Good preflight checks include:

- required arguments;
- required commands;
- target identity before destructive work;
- required permissions;
- sufficient essential configuration;
- whether a non-interactive run would otherwise prompt.

Do not:

- require optional commands when a fallback exists;
- reject a system merely because its version string differs;
- perform dozens of speculative checks that do not change behaviour;
- parse human-readable command output when an exit status or machine-readable mode exists.

Prefer capability detection:

    if command -v timeout >/dev/null 2>&1; then
        have_timeout=1
    else
        have_timeout=0
    fi

---

## 6. Capture return statuses immediately

`$?` is overwritten by the next command, including `printf`, `[`, `[[` in some constructions, declarations and logging helpers.

Correct:

    result=$(external_command)
    rc=$?

    if ((rc != 0)); then
        warn "external_command returned ${rc}"
    fi

Do not insert another command between the operation and `rc=$?`.

When assigning command output to a local variable, declare and assign separately:

    local result
    result=$(external_command)
    rc=$?

Do not:

    local result=$(external_command)

The status usually reflects the `local` builtin rather than clearly preserving the command substitution’s result.

Be careful with negation:

    if ! external_command; then
        rc=$?    # This is the status after logical negation, not the original failure.
    fi

Use:

    if external_command; then
        :
    else
        rc=$?
        warn "external_command failed with status ${rc}"
    fi

---

## 7. Never suppress a failure without documenting the policy

Avoid unexplained suppression:

    command || true
    command 2>/dev/null || :
    command || exit 0

These patterns erase information and make failures impossible to diagnose.

Acceptable suppression states why the result is harmless:

    if ! rm -f -- "$optional_cache_file"; then
        warn "Could not remove optional cache file: $optional_cache_file"
    fi

Inside cleanup, where failure must not replace the original status:

    rm -f -- "${lock_file:-}" 2>/dev/null || :

Comment why suppression is safe:

    # Best-effort cleanup only. Preserve the script's original exit status.
    rm -rf -- "$tmp_dir" 2>/dev/null || :

---

## 8. Prevent hangs by design

Any operation that can wait indefinitely must have a stopping condition.

Potential blocking points include:

- network requests;
- device discovery;
- `adb wait-for-device`;
- package managers;
- DNS resolution;
- lock acquisition;
- `read`;
- `wait`;
- FIFOs and pipes;
- mounts;
- commands that unexpectedly request confirmation;
- child processes that ignore termination.

### 8.1 Prefer native timeout controls

Use the program’s own controls where possible.

For example, network clients may provide separate:

- connection timeout;
- read timeout;
- total operation timeout;
- retry count.

Native controls usually report more precise errors than an external watchdog.

### 8.2 Add an outer timeout to genuinely risky commands

Where GNU `timeout` is available:

    timeout --signal=TERM --kill-after=5s 60s risky_command
    rc=$?

    case $rc in
        0)
            log "risky_command completed"
            ;;
        124)
            warn "risky_command exceeded 60 seconds"
            ;;
        137)
            warn "risky_command did not stop after TERM and was killed"
            ;;
        *)
            warn "risky_command failed with status ${rc}"
            ;;
    esac

Do not silently run an operation unbounded when the timeout facility is missing. Either:

- use a tested platform-specific watchdog;
- use the application’s native timeout;
- skip the optional operation with a warning;
- stop before a required but potentially unbounded operation.

### 8.3 Bound polling loops

Bad:

    while ! device_is_ready; do
        sleep 1
    done

Good:

    max_attempts=30
    ready=0

    for ((attempt = 1; attempt <= max_attempts; attempt += 1)); do
        if device_is_ready; then
            ready=1
            break
        fi

        log "Device not ready; attempt ${attempt}/${max_attempts}"
        sleep 1
    done

    if ((ready == 0)); then
        warn "Device did not become ready after ${max_attempts} attempts"
    fi

Every loop must have at least one of:

- finite input;
- a maximum attempt count;
- a deadline;
- a guaranteed progress invariant;
- an externally handled cancellation path.

### 8.4 Prevent hidden prompts

For non-interactive scripts:

- use documented non-interactive options;
- provide required input explicitly;
- redirect stdin from `/dev/null` for commands that must not consume script input;
