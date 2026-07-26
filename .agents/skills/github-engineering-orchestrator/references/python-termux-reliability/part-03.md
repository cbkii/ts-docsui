- remove only owned resources;
- be idempotent;
- avoid indefinite waits;
- avoid network dependencies;
- not obscure the primary exception;
- not convert failure to success;
- not convert success to failure for harmless cleanup problems.

Do not rely on `atexit` for essential correctness. It may not run after SIGKILL, Android forced termination, fatal crashes, reboot, or `os._exit()`.

---

# 21. Signals and Android termination

Signal handlers should perform minimal work. Do not do file I/O, logging, lock acquisition, waits, or complex cleanup inside a handler.

Use a simple flag:

```python
stop_requested = False
received_signal: int | None = None


def handle_signal(signum: int, frame: FrameType | None) -> None:
    del frame

    global stop_requested
    global received_signal

    stop_requested = True
    received_signal = signum
```

Long-running loops must check the flag. Blocking operations still need timeouts.

Recommended statuses:

- `130` for Ctrl+C or SIGINT;
- `143` for SIGTERM where represented.

Python cannot catch SIGKILL. Android may kill Termux processes because of memory pressure, battery policy, phantom-process limits, force-stop, reboot, or OEM process management.

Therefore:

- write versioned checkpoints;
- make stages idempotent;
- use temporary names for incomplete output;
- write completion markers only after validation;
- avoid keeping the only valid state in memory;
- make rerun recovery explicit.

A wake lock is not a substitute for checkpoints.

---

# 22. Idempotence, checkpoints, and locks

Running a script twice must not duplicate configuration, database records, exports, or destructive transformations.

For configuration:

1. parse current state;
2. normalise;
3. apply the intended update;
4. validate;
5. serialise once;
6. replace atomically.

Do not infer completion solely from file existence. Validate format, expected members, size, checksum, target identity, or completion metadata.

A checkpoint means all effects represented by it are complete and validated.

Write checkpoints atomically and include a schema or script version.

On restart:

1. parse checkpoint;
2. validate schema;
3. verify referenced output;
4. resume only from a completed boundary;
5. restart incomplete stages;
6. stop for review when state is contradictory.

Keep locks in private storage. Record PID, run ID, start time, and script identity. Do not assume PID alone proves ownership. Remove only demonstrably stale locks; otherwise stop and report ambiguity.

---

# 23. Concurrency

Use sequential execution unless concurrency provides clear value.

Concurrency adds race conditions, hidden exceptions, shutdown complexity, memory pressure, and Android process pressure.

Bound workers conservatively:

```python
max_workers = min(4, max(1, os.cpu_count() or 1))
```

Always consume future results:

```python
with concurrent.futures.ThreadPoolExecutor(
    max_workers=max_workers
) as executor:
    futures = [
        executor.submit(process_item, item)
        for item in items
    ]

    for future in concurrent.futures.as_completed(futures):
        result = future.result()
```

Apply timeouts to futures, joins, queues, locks, and waits.

Python cannot safely force-kill a thread. Use cooperative cancellation. Use a subprocess when hard termination is genuinely required.

Test `multiprocessing` on the actual Termux and Python build before relying on it.

---

# 24. Network operations

Every network operation must have explicit time bounds.

Where supported, define connection timeout, TLS timeout, read timeout, total deadline, retry count, and maximum response size.

Do not use `requests.get(url)` without timeouts.

Example:

```python
requests.get(
    url,
    timeout=(10, 30),
)
```

Retry selectively. Do not repeatedly retry authentication rejection, malformed input, deterministic 4xx failures, or invalid configuration.

Stream large downloads, cap total bytes, write to a temporary file, then validate before replacing an existing valid file.

---

# 25. Memory, storage, and archives

Avoid loading unbounded data into memory:

```python
# Avoid for large inputs.
data = huge_file.read_bytes()
lines = huge_file.read_text().splitlines()
items = list(very_large_generator)
```

Prefer streaming:

```python
with path.open("rb") as file:
    while chunk := file.read(1024 * 1024):
        process(chunk)
```

Apply limits to file size, decompressed size, archive members, logs, subprocess output, JSON, queues, directory entries, and retries.

Writes may fail during write, flush, fsync, close, rename, or archive finalisation. Handle `errno.ENOSPC` explicitly and preserve the previous valid output.

Before extracting archives:

1. reject absolute paths;
2. normalise member paths;
3. ensure members remain under the extraction root;
4. reject or explicitly handle symlinks;
5. cap member count and expanded size;
6. extract privately;
7. validate contents;
8. move or export only accepted results.

Do not use unrestricted `extractall()` on untrusted archives.

---

# 26. Logging and progress

Use stdout for requested machine-readable data and stderr for progress, warnings, errors, and summaries.

```python
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stderr,
)
```

Do not mix progress text into JSON, CSV, or another stdout data stream.

Use parameterised logging:

```python
logger.info("Processing %s", path)
```

Use `logger.exception()` only inside an exception handler.

Do not log passwords, cookies, tokens, API keys, private keys, authorisation headers, credential-bearing URLs, unredacted environment dumps, or sensitive command arguments.

Long-running scripts should report stage boundaries:

```text
[1/6] Validating environment
[2/6] Inspecting inputs
[3/6] Collecting data
[4/6] Processing results
[5/6] Writing output
[6/6] Validating and finalising
```

For long stages, report items, bytes, elapsed time, retry count, or current phase. Do not flood output with every successful low-level action.

Support an explicit `--debug` mode. Debug mode must not expose secrets or change core control flow.

---

# 27. Exit statuses and summary

Recommended statuses:

- `0`: essential result completed successfully;
- `1`: expected operational failure;
- `2`: invalid invocation or configuration;
- `3`: stopped because continuing would be unsafe;
- `70`: unexpected internal software failure;
- `130`: interrupted by SIGINT;
- `143`: terminated by SIGTERM where represented.

Warnings may still return `0` when the required result is valid.

Do not return `0` when required output is missing, validation failed, output is incomplete, destructive state is ambiguous, or an unexpected exception occurred.

Every multi-stage script should finish with one of:

- `SUCCESS`;
- `COMPLETED WITH WARNINGS`;
- `FAILED`;
- `STOPPED FOR SAFETY`;
- `INTERRUPTED`.

Example:

```text
==================================================
RESULT:                    COMPLETED WITH WARNINGS
Required stages complete: 6
Optional stages skipped:  2
Warnings:                 3
Errors:                   0
Output:                   /path/to/output
Detailed log:             /path/to/run.log
==================================================
```

Do not report success merely because no exception escaped. Validate the promised result first.

---

# 28. Android system-change workflow

For Android, root, Magisk, or configuration scripts, use this order:

1. Inspect current state.
2. Validate target identity.
3. Record before-state.
4. Build the plan.
5. Report intended change.
6. Apply one logical change.
7. Verify immediate result.
8. Record restart or reboot requirement.
9. Checkpoint the completed stage.
10. Continue only when verification permits it.

Do not apply unrelated changes in parallel.

Do not continue applying later changes after a required verification fails.

Do not clean evidence before the root cause is captured.

Classify each change as requiring no restart, app restart, service restart, zygote restart, or full reboot.

Do not claim success solely because a write command returned `0`.

---

# 29. Reusable subprocess helper

Use this only for commands with bounded, reasonably small output:

```python
from __future__ import annotations

import os
import signal
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence


@dataclass(frozen=True)
class CommandResult:
    args: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


class CommandError(OperationalError):
    pass


def run_command(
    args: Sequence[str | os.PathLike[str]],
    *,
    timeout: float,
    ok_codes: frozenset[int] = frozenset({0}),
    cwd: Path | None = None,
    env: Mapping[str, str] | None = None,
) -> CommandResult:
    if timeout <= 0:
        raise ValueError("timeout must be greater than zero")

    command = tuple(os.fspath(arg) for arg in args)

    if not command:
        raise ValueError("args must not be empty")

    try:
        process = subprocess.Popen(
            command,
            cwd=cwd,
            env=dict(env) if env is not None else None,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            start_new_session=True,
        )
    except FileNotFoundError as exc:
        raise CommandError(
            f"Command not found: {command[0]}"
        ) from exc
    except OSError as exc:
        raise CommandError(
            f"Could not start {command[0]}: {exc}"
        ) from exc

    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

            stdout, stderr = process.communicate()

        raise CommandError(
            f"Command exceeded {timeout:.1f} seconds: {command[0]}"
        ) from exc

    result = CommandResult(
