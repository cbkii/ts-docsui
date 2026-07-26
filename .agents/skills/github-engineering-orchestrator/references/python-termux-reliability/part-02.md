Provide a separate explicit bootstrap step.

Use:

```bash
python -m pip
```

rather than bare `pip`.

Keep virtual environments under private Termux storage:

```bash
python -m venv "$HOME/.venvs/project-name"
"$HOME/.venvs/project-name/bin/python" -m pip install ...
```

Pin dependency ranges or exact versions sufficiently for reproducibility.

Do not silently start long source builds because an Android wheel is unavailable.

---

# 10. Environment variables

Treat environment variables as optional, untrusted input.

Prefer:

```python
raw_output = os.environ.get("OUTPUT_DIR")
output = Path(raw_output) if raw_output else default_output
```

Validate values:

```python
raw_timeout = os.environ.get("SCRIPT_TIMEOUT", "60")

try:
    timeout = float(raw_timeout)
except ValueError as exc:
    raise ConfigError(
        f"SCRIPT_TIMEOUT must be numeric, not {raw_timeout!r}"
    ) from exc

if timeout <= 0:
    raise ConfigError("SCRIPT_TIMEOUT must be greater than zero")
```

Normally copy the current environment for subprocesses:

```python
child_env = os.environ.copy()
child_env["LC_ALL"] = "C"
```

A minimal replacement environment can accidentally remove `PATH`, `HOME`, `PREFIX`, loader settings, or credentials intentionally provided by the caller.

For a specific Android command, sanitise only that command’s environment.

---

# 11. Bound every uncertain wait

Every potentially blocking operation must have a timeout, deadline, maximum attempts, finite input, or documented cancellation mechanism.

Potential blockers include:

- subprocesses;
- network and DNS;
- sockets;
- `input()`;
- device discovery;
- locks;
- queues;
- `Thread.join()`;
- `Future.result()`;
- `Process.join()`;
- named pipes;
- stream reads;
- archive extraction;
- filesystem walks over unavailable mounts;
- native extension calls.

No loop may depend on “eventually”.

Use `time.monotonic()` for deadlines:

```python
deadline = time.monotonic() + timeout

while True:
    if condition_is_ready():
        break

    remaining = deadline - time.monotonic()

    if remaining <= 0:
        raise TimeoutError(
            f"Condition was not met within {timeout:.1f} seconds"
        )

    time.sleep(min(0.5, remaining))
```

Do not use wall-clock time for elapsed-time control.

Retries must be selective, finite, visible, and covered by a total deadline.

Do not retry invalid configuration, syntax errors, unsupported operations, deterministic permission denial, malformed data, missing required files, or target identity mismatch.

---

# 12. Interactive input

A script intended for unattended use must not unexpectedly prompt.

Before `input()`:

```python
if not sys.stdin.isatty() or not sys.stdout.isatty():
    raise ConfigError(
        "Confirmation is required, but no interactive terminal is available"
    )
```

Support explicit modes such as:

```text
--yes
--non-interactive
--dry-run
```

Do not default to “yes” for destructive work.

For subprocesses that must not prompt or consume script input:

```python
stdin=subprocess.DEVNULL
```

---

# 13. Subprocess rules

Use argument lists:

```python
subprocess.run(
    ["getprop", "ro.build.version.release"],
    ...
)
```

Do not build shell strings unless shell syntax is genuinely required:

```python
# Avoid.
subprocess.run(
    f"getprop {property_name}",
    shell=True,
)
```

Default to `shell=False`. Avoid `os.system()` and `os.popen()`.

Use `check=True` only when every non-zero status means failure.

For meaningful non-zero statuses:

```python
completed = subprocess.run(
    ["grep", "-q", pattern, filename],
    check=False,
    timeout=10,
)

if completed.returncode == 0:
    found = True
elif completed.returncode == 1:
    found = False
else:
    raise OperationalError(
        f"grep failed with status {completed.returncode}"
    )
```

Do not treat stderr output alone as failure.

Always bound uncertain commands with `timeout=`.

When using `Popen` with pipes, use `communicate(timeout=...)`. Do not call `wait()` while unread stdout or stderr may fill.

Do not capture unbounded output in memory. Redirect large output to a private file and validate it.

For text output, specify:

```python
text=True,
encoding="utf-8",
errors="replace",
```

Use bytes when exact binary output matters.

---

# 14. Terminate subprocess trees

A child may create descendants. Killing only the direct child can leave workers, locks, mounts, listeners, or privileged helpers.

Start the child in its own session:

```python
process = subprocess.Popen(
    args,
    start_new_session=True,
    stdin=subprocess.DEVNULL,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    encoding="utf-8",
    errors="replace",
)
```

On timeout, terminate the process group, wait briefly, then kill if necessary.

Do not call `killpg()` unless the child was intentionally placed in a dedicated process group or session.

Do not kill by broad process-name matching when a PID or process group is known.

---

# 15. Root operations

Do not run the entire Python script as root merely because one operation requires root.

Preferred sequence:

1. Run Python as the normal Termux user.
2. Inspect and validate state.
3. Build one narrow privileged operation.
4. Invoke root only for that operation.
5. Verify the result as the normal user.

`su -c` normally accepts a shell command string. Do not interpolate untrusted data into it.

Avoid:

```python
command = f"rm -rf {user_path}"
subprocess.run(["su", "-c", command])
```

Prefer fixed root helpers, secure temporary files, absolute paths, strict target validation, and minimal privilege scope.

Do not run Termux package management as root.

Consider ownership changes caused by root-created files under `$HOME`.

---

# 16. Termux and Android commands

Termux binaries normally live under `$PREFIX/bin`. Android system binaries normally live under `/system/bin`.

Do not assume a basename resolves to the intended implementation.

Use `shutil.which()` for Termux commands.

Use absolute Android paths when identity matters:

```text
/system/bin/am
/system/bin/pm
/system/bin/settings
/system/bin/getprop
```

Termux loader and PATH variables can interfere with Android commands. Scope any sanitised environment to the specific command:

```python
android_env = os.environ.copy()
android_env["PATH"] = "/system/bin"
android_env.pop("LD_PRELOAD", None)
android_env.pop("LD_LIBRARY_PATH", None)
```

Permission denial under the Termux UID is not automatically retryable.

---

# 17. Path and filename handling

Use `pathlib.Path`.

Do not depend on the caller’s working directory unless the interface explicitly says so.

Distinguish script-relative resources, caller-relative input, Termux-private state, temporary state, and shared-storage exports.

Avoid global `os.chdir()`. Prefer explicit paths and subprocess `cwd=`.

Before destructive work, resolve and contain targets:

```python
resolved_target = target.expanduser().resolve(strict=False)
resolved_root = allowed_root.expanduser().resolve(strict=True)

if resolved_target == resolved_root:
    raise SafetyStop(
        f"Refusing to operate on allowed root itself: {resolved_target}"
    )

if not resolved_target.is_relative_to(resolved_root):
    raise SafetyStop(
        f"Target is outside allowed root: {resolved_target}"
    )
```

Also reject empty paths, `/`, `.`, `..`, `$HOME`, `$PREFIX`, shared-storage roots, and ambiguous unresolved targets unless explicitly intended.

Do not use string-prefix checks as the sole containment test.

Treat filenames as arbitrary strings. Do not parse `ls`. Do not concatenate filenames into shell commands. Use Python APIs or subprocess argument lists.

Do not follow symlinks recursively unless required. Bound traversal by root, depth, filesystem, item count, or time where appropriate.

---

# 18. Text and binary data

Specify encodings for persistent text:

```python
path.read_text(encoding="utf-8")
path.write_text(text, encoding="utf-8", newline="\n")
```

For diagnostics containing arbitrary bytes:

```python
text = path.read_text(
    encoding="utf-8",
    errors="replace",
)
```

Use `errors="replace"` only when exact byte preservation is unnecessary.

Do not use `errors="ignore"` unless data loss is explicitly acceptable and reported.

Use binary mode for exact round-tripping.

Successful parsing does not prove semantic validity. Validate types, required keys, ranges, and schema version.

---

# 19. Atomic file replacement

Do not write directly over important files.

Required pattern:

1. Create a temporary file in the destination directory.
2. Write complete content.
3. Flush Python buffers.
4. `fsync()` when durability matters.
5. Validate the temporary file.
6. Apply permissions where supported.
7. Replace using `os.replace()`.
8. Optionally fsync the parent directory.
9. Remove the temporary file on failure.

Reference:

```python
def atomic_write_bytes(path: Path, data: bytes) -> None:
    path = path.expanduser()
    path.parent.mkdir(parents=True, exist_ok=True)

    fd, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
    )
    temporary_path = Path(temporary_name)

    try:
        with os.fdopen(fd, "wb") as file:
            file.write(data)
            file.flush()
            os.fsync(file.fileno())

        os.replace(temporary_path, path)

    except BaseException:
        try:
            temporary_path.unlink(missing_ok=True)
        except OSError:
            pass
        raise
```

The temporary file must be on the same filesystem as the destination.

Do not assume shared storage provides equivalent atomicity or durability.

For archives, create under a temporary name, close fully, reopen and validate, optionally checksum, then replace or export.

---

# 20. Temporary resources and cleanup

Use `tempfile.TemporaryDirectory()`, `NamedTemporaryFile()`, `mkstemp()`, or `mkdtemp()`.

Do not construct predictable temporary names from PID or timestamp alone.

Prefer private Termux storage as the temporary root.

Use context managers for files, temporary directories, databases, locks, sockets, archives, HTTP responses, and subprocess resources.

Do not rely on garbage collection or `__del__()` for important cleanup.

Cleanup must:

- tolerate partial initialisation;
