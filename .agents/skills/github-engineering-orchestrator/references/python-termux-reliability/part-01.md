# Python “Just Run” Reliability Standard for Android Termux

## Purpose

Use this document when writing, reviewing, repairing, or finalising Python scripts intended to run in Android Termux.

The goal is predictable execution, not maximum strictness. A reliable script should:

- avoid spurious failures and unnecessary early exits;
- distinguish expected conditions from real failures;
- bound subprocesses, network requests, retries, waits, queues and locks;
- preserve the last valid state until replacements are complete;
- degrade gracefully when optional features fail;
- stop when destructive safety cannot be proven;
- recover safely after interruption or Android process termination;
- report exactly what completed, failed, or was skipped;
- be safe to run again.

The governing principle is:

> **Explicit policy beats broad exception handling.**

A “just run” script does not continue at all costs and does not abort at every anomaly. It handles each foreseeable outcome intentionally.

---

# 1. Priority order

When requirements conflict, use this order:

1. **Safety and target correctness**
2. **Validity of the required result**
3. **Recovery after interruption**
4. **Bounded execution**
5. **Clear diagnostics**
6. **Graceful degradation**
7. **Convenience**
8. **Compactness or stylistic elegance**

Never weaken a destructive safety guard merely to make a script continue.

---

# 2. Classify every operation

Before coding, classify each meaningful operation.

## Expected condition

The result is normal control flow.

Examples:

- optional file absent;
- search returns no matches;
- process not running;
- Android property unavailable;
- optional configuration omitted.

Policy:

- handle the specific result;
- do not print a traceback;
- do not count it as an error;
- continue through the intended branch.

## Optional operation

Failure does not invalidate the core result.

Policy:

- catch only expected exceptions;
- warn once with useful context;
- use a fallback or skip the feature;
- continue;
- include the warning in the final summary.

## Retryable operation

Failure may be temporary.

Policy:

- retry only known transient failures;
- cap attempts and total elapsed time;
- use bounded delay or backoff;
- preserve the final error;
- stop retrying permanent failures immediately.

## Required operation

Failure prevents a correct essential result.

Policy:

- raise a domain-specific operational exception;
- preserve the original cause;
- clean up owned resources where possible;
- stop at a controlled top-level boundary;
- return a documented non-zero status.

## Unsafe-to-continue condition

Continuing could modify the wrong target, delete unrelated data, write invalid state, or produce misleading output.

Policy:

- report `STOP:` and the exact reason;
- do not attempt speculative recovery;
- preserve evidence;
- return a distinct non-zero status.

---

# 3. Termux execution model

Termux is not a conventional desktop Linux distribution.

Assume:

- Python runs natively on Android;
- Android uses bionic rather than glibc;
- Termux uses a non-standard prefix;
- the app runs under Android sandboxing and SELinux;
- commands available in `adb shell` may behave differently from the Termux app UID;
- Android may pause or kill the process without allowing Python cleanup.

Common paths are:

```text
HOME=/data/data/com.termux/files/home
PREFIX=/data/data/com.termux/files/usr
```

Do not hard-code these throughout the script:

```python
from pathlib import Path
import os

HOME = Path.home()
PREFIX = Path(os.environ.get("PREFIX", "/data/data/com.termux/files/usr"))
```

## Private storage versus shared storage

Keep these in Termux private storage:

- scripts;
- virtual environments;
- temporary files;
- locks;
- databases;
- checkpoints;
- authoritative configuration;
- incomplete archives;
- active working directories.

Treat Android shared storage mainly as import/export storage:

```text
/sdcard
/storage/emulated/0
~/storage/shared
```

Shared storage may not reliably support normal POSIX behaviour for permissions, ownership, symlinks, sockets, locks, case sensitivity, exact timestamps, or atomic replacement.

Preferred workflow:

1. Read or copy input from shared storage.
2. Work in private Termux storage.
3. Validate completed output.
4. Export the final result.
5. Keep checkpoint and recovery state private.

Do not place virtual environments or live SQLite databases on shared storage.

---

# 4. Interpreter and entry point

For a Termux-only script:

```python
#!/data/data/com.termux/files/usr/bin/python
```

For a portable script normally invoked explicitly:

```python
#!/usr/bin/env python3
```

Do not assume `/usr/bin/python3` exists in Termux.

Do not rely on direct execution from shared storage. Prefer:

```bash
python script.py
```

Declare the minimum Python version actually required:

```python
import sys

MIN_PYTHON = (3, 11)

if sys.version_info < MIN_PYTHON:
    print(
        f"ERROR: Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]} or newer is required; "
        f"found {sys.version.split()[0]}",
        file=sys.stderr,
    )
    raise SystemExit(1)
```

Use one controlled entry point:

```python
def main(argv: list[str] | None = None) -> int:
    ...
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

Do not perform significant work at import time. Import-time code must not modify files, access the network, run subprocesses, request root, parse arguments, prompt, acquire locks, start threads, or modify Android state.

Helper functions should return results or raise exceptions. They should not call `sys.exit()`.

---

# 5. Arguments and configuration

Use `argparse` for non-trivial command-line interfaces.

Parse and validate arguments before side effects:

```python
import argparse
from pathlib import Path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Collect and package diagnostics.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path.cwd() / "output",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=60.0,
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--debug", action="store_true")
    return parser
```

Validate semantics explicitly:

```python
if args.timeout <= 0:
    parser.error("--timeout must be greater than zero")
```

Do not use `assert` for user input, configuration, path safety, permissions, target identity, or runtime availability. Assertions may be disabled with `python -O`.

Defaults are appropriate only for omitted optional settings. Do not silently replace malformed required configuration with defaults.

---

# 6. Exception-handling rules

## Catch narrowly

Preferred:

```python
try:
    data = path.read_text(encoding="utf-8")
except FileNotFoundError:
    data = default_data
except PermissionError as exc:
    raise OperationalError(
        f"Cannot read {path}: permission denied"
    ) from exc
```

Avoid:

```python
try:
    data = path.read_text()
except Exception:
    data = default_data
```

Broad handlers can hide programming defects, encoding errors, resource exhaustion, API changes, path mistakes, and failures inside fallback code.

Catch an exception only where the code can recover, classify it, add context, or perform required cleanup.

Preserve causes:

```python
try:
    config = json.loads(text)
except json.JSONDecodeError as exc:
    raise ConfigError(
        f"Invalid JSON in {config_path} at "
        f"line {exc.lineno}, column {exc.colno}"
    ) from exc
```

Do not catch `BaseException` during normal operation. A bare handler also catches `KeyboardInterrupt` and `SystemExit`.

A bare or `BaseException` handler is acceptable only for minimal cleanup followed by immediate re-raise:

```python
try:
    ...
except BaseException:
    cleanup_best_effort()
    raise
```

Never suppress an active exception accidentally:

```python
# Wrong: return in finally can hide the real failure.
try:
    perform_work()
finally:
    return 0
```

Avoid unexplained patterns such as:

```python
except Exception:
    pass
```

or ambiguous fallbacks such as returning `None` for every failure.

---

# 7. Domain-specific exceptions

Use a small hierarchy:

```python
class ScriptError(Exception):
    """Base class for expected script failures."""


class ConfigError(ScriptError):
    """Invalid invocation or configuration."""


class OperationalError(ScriptError):
    """Required work could not be completed."""


class SafetyStop(ScriptError):
    """Continuing would be unsafe."""
```

Top-level policy:

```python
try:
    return run(args)
except SafetyStop as exc:
    logger.critical("STOP: %s", exc)
    return 3
except ConfigError as exc:
    logger.error("%s", exc)
    return 2
except OperationalError as exc:
    logger.error("%s", exc)
    return 1
except Exception:
    logger.exception("Unexpected internal failure")
    return 70
```

Expected operational failures should not emit unnecessary tracebacks. Unexpected `TypeError`, `AttributeError`, `IndexError`, or invariant failures should remain visible as programming defects.

---

# 8. Preflight without over-checking

Perform preflight once for stable facts:

- supported Python version;
- required arguments;
- required modules;
- required external commands;
- writable private work directory;
- required input;
- root availability where genuinely required.

Recheck only facts that may change:

- removable storage;
- device connection;
- network state;
- free space;
- target identity immediately before destructive work.

Do not fail because an optional command is absent when a fallback exists.

Prefer capability detection:

```python
import shutil

if shutil.which("tar") is None:
    logger.warning("tar unavailable; using Python tarfile fallback")
```

For optional modules, isolate the import:

```python
try:
    import optional_module
except ImportError:
    optional_module = None
```

Do not wrap unrelated initialisation in the same `ImportError` handler.

---

# 9. Dependency policy

Operational scripts must not silently modify their environment.

Do not automatically run during normal execution:

```text
pkg upgrade
apt install ...
pip install ...
pip install --upgrade ...
```

