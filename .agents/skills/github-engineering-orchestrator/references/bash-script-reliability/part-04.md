
Do not depend unnecessarily on:

- the caller’s current directory;
- aliases;
- locale-specific output;
- interactive shell settings;
- inherited `IFS`;
- an arbitrary `PATH`;
- terminal width;
- colour support;
- user-specific command configuration.

Set `IFS` locally when reading:

    while IFS= read -r line; do
        ...
    done

When parsing output that is unavoidably locale-dependent, scope the locale:

    result=$(LC_ALL=C external_command)

Do not globally force a locale unless every operation has been tested under it.

Use a conservative `umask` when creating sensitive files:

    umask 077

Do not overwrite `PATH` with a narrow fixed value unless the deployment environment is fully controlled. Add required paths deliberately or resolve dependencies during preflight.

---

## 22. Use exit statuses as a documented API

Recommended top-level meanings:

- `0`: the script’s essential outcome was achieved;
- `1`: an operational failure prevented the essential outcome;
- `2`: invalid invocation or arguments.

Warnings about optional operations may still produce status `0` when the promised result is valid.

Do not return non-zero merely because:

- an optional tool was absent;
- an expected file was not present;
- a best-effort cleanup failed;
- an informational probe was denied;
- one fallback failed but another succeeded.

Do not repurpose conventional shell statuses casually:

- `126`: command found but not executable;
- `127`: command not found;
- values greater than 128 commonly indicate signal termination;
- GNU `timeout` commonly uses `124` for expiry and `137` after forced kill.

Functions return status codes, not arbitrary data. Status values are limited. Return structured data through stdout, files or named variables.

---

## 23. Always print a final summary

A collection or multi-stage script should end with a concise summary even when some optional stages failed.

Example:

    ==================================================
    RESULT: COMPLETED WITH WARNINGS
    Required stages completed: 7
    Optional stages skipped:   2
    Warnings:                  3
    Required failures:         0
    Output directory:          /path/to/results
    Log file:                  /path/to/run.log
    ==================================================

Use one of:

- `SUCCESS`;
- `COMPLETED WITH WARNINGS`;
- `FAILED`;
- `STOPPED FOR SAFETY`;
- `INTERRUPTED`.

Identify:

- what completed;
- what did not;
- whether the core result is usable;
- where outputs and logs were written;
- any exact manual action still required.

Do not finish silently after a long operation.

---

## 24. Provide opt-in debugging

Normal runs should be readable. Detailed tracing should be optional.

Example:

    if [[ ${DEBUG:-0} == 1 ]]; then
        PS4='+ ${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:-main}: '
        set -x
    fi

Never enable `set -x` unconditionally in a script that handles:

- passwords;
- tokens;
- cookies;
- private keys;
- signed URLs;
- sensitive environment variables.

Disable tracing around sensitive commands if debugging may be enabled:

    { set +x; } 2>/dev/null
    sensitive_command "$secret"
    if [[ ${DEBUG:-0} == 1 ]]; then
        set -x
    fi

---

## 25. Required validation before delivery

Every non-trivial script must pass:

    bash -n script.sh
    shellcheck script.sh

A ShellCheck warning may be suppressed only when:

- the author understands the warning;
- the behaviour is intentional;
- the suppression is narrowly scoped;
- a comment explains why.

Test on the actual minimum supported Bash version and target operating system.

Required test cases should include:

- normal successful run;
- second run over existing state;
- path containing spaces;
- path beginning with `-`;
- empty input;
- empty glob;
- missing optional command;
- missing required command;
- permission-denied output;
- read-only destination;
- failed network operation;
- timeout;
- interrupted run;
- no interactive terminal;
- stdin redirected from a file or pipe;
- partial output from a prior run;
- cleanup after failure;
- cleanup before all variables are initialised;
- child-process failure;
- unexpected non-zero status in every pipeline component.

For scripts processing filenames, also test tabs, wildcard characters, quotes, backslashes and newlines.

---

## 26. Complexity limit

Bash is appropriate when the script primarily coordinates commands and performs limited data manipulation.

Consider a more structured language when the script requires substantial:

- nested state management;
- concurrency;
- structured data processing;
- protocol implementation;
- complex retry graphs;
- transaction management;
- error-object propagation;
- parsing of JSON, XML or binary formats without dedicated tools.

Do not compensate for excessive complexity with more traps, global flags, `eval`, generated shell code or deeply nested conditionals.

A short Bash launcher around a reliable Python or compiled implementation is often more dependable than several hundred lines of stateful shell logic.

---

## 27. Recommended reference structure

    #!/usr/bin/env bash

    # No blanket set -e or set -u.
    # Enable pipefail only for audited pipelines or scoped subshells.

    readonly SCRIPT_NAME=${0##*/}

    warning_count=0
    error_count=0
    tmp_dir=''
    worker_pid=''

    log() {
        printf '[INFO] %s\n' "$*" >&2
    }

    warn() {
        printf '[WARN] %s\n' "$*" >&2
        ((warning_count += 1))
    }

    error() {
        printf '[ERROR] %s\n' "$*" >&2
        ((error_count += 1))
    }

    cleanup() {
        local rc=$?

        trap - EXIT INT TERM

        if [[ -n ${worker_pid:-} ]] &&
           kill -0 "$worker_pid" 2>/dev/null; then
            kill -TERM "$worker_pid" 2>/dev/null || :
            wait "$worker_pid" 2>/dev/null || :
        fi

        if [[ -n ${tmp_dir:-} && -d ${tmp_dir:-} ]]; then
            rm -rf -- "$tmp_dir" 2>/dev/null || :
        fi

        exit "$rc"
    }

    print_summary() {
        local result=$1

        printf '\n' >&2
        printf '========================================\n' >&2
        printf 'RESULT:   %s\n' "$result" >&2
        printf 'WARNINGS: %d\n' "$warning_count" >&2
        printf 'ERRORS:   %d\n' "$error_count" >&2
        printf '========================================\n' >&2
    }

    require_command() {
        local command_name=$1

        if ! command -v "$command_name" >/dev/null 2>&1; then
            error "Required command not found: $command_name"
            return 1
        fi
    }

    preflight() {
        local failed=0

        require_command find || failed=1
        require_command mktemp || failed=1

        if ((failed != 0)); then
            return 1
        fi

        return 0
    }

    run_optional_probe() {
        local output
        local rc

        output=$(optional_probe 2>&1)
        rc=$?

        if ((rc != 0)); then
            warn "Optional probe failed with status ${rc}: ${output}"
            return 0
        fi

        printf '%s\n' "$output"
        return 0
    }

    perform_required_work() {
        if required_command; then
            return 0
        else
            local rc=$?
            error "Required command failed with status ${rc}"
            return "$rc"
        fi
    }

    main() {
        trap cleanup EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM

        log "[1/4] Validating environment"

        if ! preflight; then
            print_summary "FAILED"
            return 1
        fi

        tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/${SCRIPT_NAME}.XXXXXXXX")
        if [[ -z $tmp_dir || ! -d $tmp_dir ]]; then
            error "Cannot create temporary working directory"
            print_summary "FAILED"
            return 1
        fi

        log "[2/4] Running required work"

        if ! perform_required_work; then
            print_summary "FAILED"
            return 1
        fi

        log "[3/4] Running optional diagnostics"
        run_optional_probe || :

        log "[4/4] Finalising"

        if ((warning_count > 0)); then
            print_summary "COMPLETED WITH WARNINGS"
        else
            print_summary "SUCCESS"
        fi

        return 0
    }

    main "$@"

---

## 28. Agent/developer acceptance checklist

Before declaring a script final, verify all of the following:

- [ ] The interpreter matches the syntax used.
- [ ] The script does not depend on the caller’s current directory.
- [ ] `set -euo pipefail` was not added mechanically.
- [ ] Every non-zero result has an intentional classification.
- [ ] Expected negative checks are not reported as failures.
- [ ] Optional failures warn and continue.
- [ ] Required failures stop through a controlled path.
- [ ] Return statuses are captured immediately.
- [ ] No unexplained `|| true`, `|| :` or broad stderr suppression exists.
- [ ] Every potentially blocking operation is bounded.
- [ ] Every polling or retry loop has a maximum.
- [ ] Background PIDs are recorded and explicitly waited for.
- [ ] Interruptions trigger safe cleanup.
- [ ] Cleanup preserves the original exit status.
- [ ] Cleanup tolerates partial initialisation.
- [ ] All variable expansions used as arguments are quoted.
- [ ] Arrays are used for argument lists.
- [ ] `eval` is absent unless technically unavoidable and independently reviewed.
- [ ] User-controlled paths are preceded by `--` where supported.
- [ ] Recursive filename processing is NUL-delimited.
- [ ] No `ls` output is parsed.
- [ ] Pipeline subshell behaviour has been considered.
- [ ] Temporary files are created securely.
- [ ] Important file replacement is atomic where practical.
- [ ] Destructive targets have explicit safety validation.
- [ ] Operations are idempotent or have recovery checkpoints.
- [ ] Logs identify meaningful stages and failures.
- [ ] A final success/warning/failure summary is always produced.
- [ ] Debug tracing is opt-in and does not expose secrets.
- [ ] `bash -n` passes.
- [ ] ShellCheck passes or every suppression is narrowly justified.
- [ ] The script was tested on the actual target environment.
- [ ] The script was tested with missing tools, failed commands, timeouts and interruption.
- [ ] The script can be rerun safely after a partial run.

The governing principle is:

    Explicit policy beats implicit shell behaviour.

A reliable script does not merely continue at all costs and does not terminate at every anomaly. It knows which result matters, bounds every uncertain wait, preserves evidence, cleans up what it owns and reports exactly what succeeded.
