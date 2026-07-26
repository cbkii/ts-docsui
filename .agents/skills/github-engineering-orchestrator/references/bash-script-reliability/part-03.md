- detect whether a terminal is available before prompting.

Example:

    if [[ -t 0 && -t 1 ]]; then
        read -r -p "Continue? [y/N] " reply
    else
        reply='N'
        warn "No interactive terminal is available; using the safe default"
    fi

Do not add automatic `-y` confirmation to destructive commands unless the target has already been validated.

### 8.5 Manage background processes explicitly

When starting a background process:

    worker_command &
    worker_pid=$!

Record its PID immediately.

Later:

    if wait "$worker_pid"; then
        log "Worker completed"
    else
        rc=$?
        warn "Worker exited with status ${rc}"
    fi

Do not call bare `wait` unless waiting for every current child is intentional.

Cleanup must terminate owned background processes:

    if [[ -n ${worker_pid:-} ]] && kill -0 "$worker_pid" 2>/dev/null; then
        kill -TERM "$worker_pid" 2>/dev/null || :
        wait "$worker_pid" 2>/dev/null || :
    fi

Never kill processes based only on a broad name match when a recorded PID is available.

---

## 9. Make retries bounded and selective

Retries are appropriate only for failures likely to be transient.

Do not retry:

- invalid arguments;
- missing required files;
- authentication rejection unless credentials may actually refresh;
- unsupported commands;
- syntax errors;
- permission denial that cannot change;
- target identity mismatch.

Reference pattern:

    run_with_retry() {
        local max_attempts=$1
        local delay_seconds=$2
        shift 2

        local attempt
        local rc=1

        for ((attempt = 1; attempt <= max_attempts; attempt += 1)); do
            if "$@"; then
                return 0
            else
                rc=$?
            fi

            if ((attempt < max_attempts)); then
                warn "Attempt ${attempt}/${max_attempts} failed with status ${rc}; retrying"
                sleep "$delay_seconds"
            fi
        done

        return "$rc"
    }

The caller must still decide whether final failure is fatal or optional.

Do not create nested retry layers without a total deadline. Three layers of five retries can unexpectedly produce 125 attempts.

---

## 10. Quote expansions and preserve argument boundaries

Quote variable and command expansions unless intentional splitting or pattern expansion is explicitly required:

    printf '%s\n' "$value"
    cp -- "$source" "$destination"
    command "${arguments[@]}"

Do not:

    cp $source $destination
    for item in $items
    command $flags

Unquoted expansions are subject to word splitting and pathname expansion.

Use `--` before user-controlled or variable path arguments where the command supports it:

    rm -- "$file"
    mv -- "$source" "$destination"

This prevents a filename such as `-rf` from being interpreted as an option.

Use explicit paths for globs:

    for file in ./*; do
        ...
    done

rather than:

    for file in *; do
        ...
    done

Handle unmatched globs intentionally. In Bash, scope `nullglob` where appropriate:

    (
        shopt -s nullglob
        files=("$directory"/*.log)
        process_files "${files[@]}"
    )

Do not globally change glob behaviour unless every use has been audited.

---

## 11. Use arrays for command arguments

Never build a command as one quoted string.

Bad:

    options='--output "/path with spaces" --verbose'
    tool $options

Bad:

    command_string="tool --output '$path'"
    eval "$command_string"

Good:

    options=(
        --output "$path"
        --verbose
    )

    tool "${options[@]}"

Arrays preserve each argument exactly, including spaces, wildcard characters and empty strings.

Avoid `eval`. It introduces a second parsing pass, makes quoting difficult to reason about and can convert data into executable shell syntax.

---

## 12. Handle filenames as arbitrary data

Filenames may contain:

- spaces;
- tabs;
- wildcard characters;
- leading hyphens;
- quotes;
- backslashes;
- newlines.

Do not parse `ls`.

Bad:

    for file in $(ls "$directory"); do
        ...
    done

For globs:

    for file in "$directory"/*; do
        [[ -e $file ]] || continue
        process_file "$file"
    done

For recursive traversal, use NUL delimiters:

    while IFS= read -r -d '' file; do
        process_file "$file"
    done < <(find "$directory" -type f -print0)

Use:

    while IFS= read -r line; do
        ...
    done < "$input_file"

`read -r` prevents backslashes from being consumed as escape characters.

Do not use command substitution for binary data. Command substitution also removes trailing newline characters.

---

## 13. Avoid pipeline subshell surprises

A loop placed on the right side of a pipe commonly runs in a subshell. Variable changes may disappear when the pipeline ends.

Bad:

    found=0

    producer | while IFS= read -r line; do
        found=1
    done

    printf '%s\n' "$found"    # May still print 0.

Use process substitution:

    found=0

    while IFS= read -r line; do
        found=1
    done < <(producer)

Or use `mapfile`/`readarray` when retaining all records is appropriate:

    mapfile -t lines < <(producer)

Do not enable obscure shell options merely to change pipeline execution semantics unless the whole script depends on and documents them.

---

## 14. Keep functions predictable

Each function should:

- perform one coherent task;
- accept inputs through arguments;
- use local variables;
- return only an exit status;
- send returned data to stdout only when that is the function’s documented interface;
- send logs and diagnostics to stderr;
- avoid unexpectedly changing the caller’s directory, shell options, traps or global variables.

Pattern:

    inspect_target() {
        local target=$1
        local result
        local rc

        result=$(inspection_command -- "$target")
        rc=$?

        if ((rc != 0)); then
            error "Inspection failed for: $target"
            return "$rc"
        fi

        printf '%s\n' "$result"
        return 0
    }

Use a subshell for temporary directory changes:

    (
        cd -- "$work_dir" || exit 1
        perform_work
    )
    rc=$?

This prevents an unsuccessful or forgotten `cd` reversal from corrupting later paths.

Use a `main` function for non-trivial scripts:

    main() {
        parse_arguments "$@" || return
        preflight || return
        perform_work || return
        print_summary
    }

    main "$@"
    exit $?

Do not place hidden executable statements between function definitions.

---

## 15. Separate data output from diagnostics

Use stdout for requested machine-readable data.

Use stderr for:

- progress;
- warnings;
- errors;
- debug traces;
- human-readable summaries when stdout is an export stream.

Logging helpers:

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

    fatal() {
        printf '[FATAL] %s\n' "$*" >&2
        exit 1
    }

Do not place variables directly in a `printf` format string:

    printf "$message\n"

Use:

    printf '%s\n' "$message"

A variable containing `%s`, `%n` or backslash sequences must remain data, not formatting instructions.

---

## 16. Provide visible progress without noise

Long-running scripts should announce meaningful stage boundaries:

    [1/6] Validating environment
    [2/6] Collecting system state
    [3/6] Inspecting files
    [4/6] Running optional diagnostics
    [5/6] Writing results
    [6/6] Finalising

For operations of unpredictable duration, print periodic progress based on:

- files processed;
- bytes transferred;
- attempts completed;
- elapsed time;
- current stage.

Avoid printing every successful low-level command. Excessive output hides the useful failure.

A script should never appear frozen merely because it is waiting normally.

---

## 17. Use secure temporary files and deterministic cleanup

Use `mktemp` or an equivalent secure facility. Do not create predictable temporary names using only `$$`, timestamps or usernames.

Bad:

    tmp_file="/tmp/my-script.$$"

Good, using syntax verified for the target platform:

    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/my-script.XXXXXXXX") || {
        fatal "Cannot create temporary directory"
    }

Never use `mktemp -u` followed by separate file creation. That reintroduces a race between selecting the name and creating it.

Register cleanup immediately after acquiring the resource.

Reference pattern:

    tmp_dir=''
    worker_pid=''

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

    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

Cleanup rules:

- preserve the original exit status;
- tolerate partial initialisation;
- never assume a variable was set;
- never make cleanup failure replace the primary failure;
- remove only resources created or owned by this invocation;
- avoid broad wildcard deletion;
- disable traps before explicitly exiting from the cleanup handler.

Do not use an `ERR` trap as the primary control-flow system. Its triggering rules largely mirror `set -e` and contain the same contextual exceptions.

---

## 18. Make file updates atomic where practical

Do not partially overwrite an important output or configuration file.

Preferred sequence:

1. Create a secure temporary file in the destination filesystem.
2. Write the complete new content.
3. Validate the temporary content.
4. Apply required permissions.
5. Rename it over the destination.
6. Remove it during cleanup if any earlier step fails.

Conceptual pattern:

    temp_output=$(mktemp "${destination}.tmp.XXXXXXXX") || {
        fatal "Cannot create temporary output beside $destination"
    }

    if generate_content > "$temp_output" &&
       validate_content "$temp_output" &&
       chmod --reference="$destination" "$temp_output" 2>/dev/null; then
        mv -f -- "$temp_output" "$destination" || {
            fatal "Cannot replace destination: $destination"
        }
        temp_output=''
    else
        fatal "New content could not be generated or validated"
    fi

The exact `mktemp` and permission commands must be tested on the target platform.

For append-only logs, write complete records with one `printf` where possible to reduce interleaving.

---

## 19. Design for interruption and reruns

A script may stop because of:

- Ctrl+C;
- termination by a service manager;
- lost terminal session;
- reboot;
- low storage;
- network loss;
- process kill;
- dependency crash.

The next run must be able to distinguish:

- completed state;
- incomplete temporary state;
- stale lock;
- valid checkpoint;
- unsafe ambiguous state.

Prefer idempotent operations:

    mkdir -p
    rm -f
    ln -sfn
    install -D
    update only when content differs

Do not append duplicate configuration blindly.

Use checkpoints only where repeating prior work is expensive or unsafe. A checkpoint must be written only after its associated stage is fully complete.

Do not mistake the existence of an output file for proof that it is complete. Validate size, format, checksum or completion metadata as appropriate.

Locks must contain enough information to identify their owner. Handle stale locks conservatively rather than deleting every existing lock automatically.

---

## 20. Validate destructive targets immediately before use

Destructive operations require stronger guards than read-only collection.

Before `rm -rf`, formatting, flashing, overwriting or recursive permission changes:

- require a non-empty target;
- canonicalise it where possible;
- reject `/`, `.`, `..` and known parent directories;
- verify expected target identity;
- use `--`;
- print the resolved target;
- ensure the operation is within the allowed root.

Example:

    delete_tree_safely() {
        local target=$1
        local allowed_root=$2

        [[ -n $target ]] || {
            error "Refusing deletion: target is empty"
            return 1
        }

        [[ $target != / && $target != . && $target != .. ]] || {
            error "Refusing deletion of unsafe target: $target"
            return 1
        }

        case $target in
            "$allowed_root"/*)
                ;;
            *)
                error "Refusing deletion outside allowed root: $target"
                return 1
                ;;
        esac

        rm -rf -- "$target"
    }

Do not weaken destructive safety guards merely to make a script continue.

---

## 21. Control environment-dependent behaviour
