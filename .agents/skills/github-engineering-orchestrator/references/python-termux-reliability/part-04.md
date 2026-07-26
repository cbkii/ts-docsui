        args=command,
        returncode=process.returncode,
        stdout=stdout,
        stderr=stderr,
    )

    if result.returncode not in ok_codes:
        detail = result.stderr.strip() or result.stdout.strip()

        if len(detail) > 2000:
            detail = detail[:2000] + "\n...<truncated>"

        message = (
            f"Command failed with status {result.returncode}: "
            f"{command[0]}"
        )

        if detail:
            message += f"\n{detail}"

        raise CommandError(message)

    return result
```

For large output, redirect to a private file instead of capturing it.

---

# 30. Recommended top-level structure

```python
#!/data/data/com.termux/files/usr/bin/python

from __future__ import annotations

import argparse
import logging
import signal
import sys
from dataclasses import dataclass
from pathlib import Path
from types import FrameType
from typing import Sequence


LOGGER = logging.getLogger("script")

EXIT_SUCCESS = 0
EXIT_OPERATIONAL_FAILURE = 1
EXIT_USAGE = 2
EXIT_SAFETY_STOP = 3
EXIT_INTERNAL_ERROR = 70
EXIT_INTERRUPTED = 130
EXIT_TERMINATED = 143

stop_requested = False
received_signal: int | None = None


class ScriptError(Exception):
    """Base class for expected script failures."""


class ConfigError(ScriptError):
    """Invalid invocation or configuration."""


class OperationalError(ScriptError):
    """Required work could not be completed."""


class SafetyStop(ScriptError):
    """Continuing would be unsafe."""


@dataclass
class RunSummary:
    required_completed: int = 0
    optional_completed: int = 0
    optional_skipped: int = 0
    warnings: int = 0
    errors: int = 0
    output: Path | None = None

    def warning(self, message: str, *args: object) -> None:
        self.warnings += 1
        LOGGER.warning(message, *args)

    def error(self, message: str, *args: object) -> None:
        self.errors += 1
        LOGGER.error(message, *args)


def handle_signal(
    signum: int,
    frame: FrameType | None,
) -> None:
    del frame

    global stop_requested
    global received_signal

    stop_requested = True
    received_signal = signum


def check_stop() -> None:
    if not stop_requested:
        return

    if received_signal == signal.SIGTERM:
        raise InterruptedError("Termination requested")

    raise KeyboardInterrupt


def configure_logging(debug: bool) -> None:
    logging.basicConfig(
        level=logging.DEBUG if debug else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stderr,
        force=True,
    )


def run(
    args: argparse.Namespace,
    summary: RunSummary,
) -> int:
    # Preflight.
    # Required stages.
    # Optional stages.
    # Result validation.
    return EXIT_SUCCESS


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    configure_logging(args.debug)

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    summary = RunSummary()
    result = "FAILED"
    exit_status = EXIT_OPERATIONAL_FAILURE

    try:
        exit_status = run(args, summary)
        result = (
            "COMPLETED WITH WARNINGS"
            if summary.warnings
            else "SUCCESS"
        )

    except KeyboardInterrupt:
        result = "INTERRUPTED"
        exit_status = EXIT_INTERRUPTED
        LOGGER.warning("Interrupted by user")

    except InterruptedError:
        result = "INTERRUPTED"
        exit_status = EXIT_TERMINATED
        LOGGER.warning("Termination requested")

    except SafetyStop as exc:
        result = "STOPPED FOR SAFETY"
        exit_status = EXIT_SAFETY_STOP
        summary.error("STOP: %s", exc)

    except ConfigError as exc:
        result = "FAILED"
        exit_status = EXIT_USAGE
        summary.error("%s", exc)

    except OperationalError as exc:
        result = "FAILED"
        exit_status = EXIT_OPERATIONAL_FAILURE
        summary.error("%s", exc)

    except Exception:
        result = "FAILED"
        exit_status = EXIT_INTERNAL_ERROR
        summary.errors += 1
        LOGGER.exception("Unexpected internal failure")

    finally:
        print_summary(result, summary)
        logging.shutdown()

    return exit_status


if __name__ == "__main__":
    raise SystemExit(main())
```

This is a reference structure. Remove abstractions the actual script does not need.

---

# 31. Validation before delivery

Every non-trivial script must pass:

```bash
python -m py_compile script.py
```

For a package:

```bash
python -m compileall -q package_directory
```

Run the project test suite.

Where adopted by the project, also use:

```bash
ruff check .
ruff format --check .
mypy package_or_script
```

Do not add multiple overlapping tools merely to appear strict.

Also test:

```bash
python -X dev -W default script.py ...
```

Test both diagnostic and normal production modes.

---

# 32. Required test scenarios

Test on the actual supported Termux and Android environment.

At minimum test:

- normal success;
- second run over existing state;
- Ctrl+C;
- SIGTERM;
- abrupt kill followed by rerun;
- missing optional dependency;
- missing required dependency;
- missing optional and required files;
- malformed configuration;
- permission denial;
- read-only output;
- low storage where practical;
- shared-storage input;
- private-storage work directory;
- path containing spaces;
- path beginning with `-`;
- Unicode filename;
- no network;
- DNS failure;
- connect and read timeout;
- subprocess timeout;
- expected and unexpected non-zero status;
- command not found;
- child process with descendants;
- large stdout or stderr;
- no TTY;
- redirected stdin;
- closed stdout consumer;
- stale lock;
- partial checkpoint;
- partial archive;
- cleanup before full initialisation;
- cleanup failure;
- optional failure after required success;
- unexpected internal exception;
- Android system command from Termux;
- root command with changed `HOME` or `PATH`;
- rerun after root-owned output.

For destructive scripts also test:

- empty target;
- `/`;
- parent traversal;
- symlink escape;
- allowed-root boundary;
- target identity mismatch;
- stale state from an older script version.

---

# 33. Agent acceptance checklist

Before declaring a script final, verify:

## Runtime and storage

- [ ] Supported Python version is declared.
- [ ] Interpreter policy works in Termux.
- [ ] The script does not assume `/usr/bin/python`.
- [ ] Scripts, venvs, locks, databases, checkpoints, and working state remain private.
- [ ] Shared storage is used mainly for import/export.
- [ ] The script was tested in real Termux.

## Structure and failure policy

- [ ] Significant work does not occur at import time.
- [ ] `main()` controls execution.
- [ ] Helper functions do not call `sys.exit()`.
- [ ] Arguments are parsed before side effects.
- [ ] Assertions are not used for runtime safety.
- [ ] Expected, optional, retryable, required, and unsafe outcomes are distinguished.
- [ ] Exceptions are caught narrowly.
- [ ] Causes are preserved with `raise ... from ...`.
- [ ] Unexpected defects retain tracebacks.
- [ ] Optional failures cannot falsely fail the run.
- [ ] Required failures cannot be mistaken for success.

## Waiting, subprocesses, and privilege

- [ ] Every uncertain subprocess has a timeout.
- [ ] Every network request has explicit time bounds.
- [ ] Every polling loop and retry policy is bounded.
- [ ] Hidden prompts are prevented.
- [ ] Commands use argument lists.
- [ ] `shell=True` is absent or independently justified.
- [ ] Large output is streamed rather than captured.
- [ ] Timed-out descendants are terminated where necessary.
- [ ] Root is requested only for narrow operations.
- [ ] Untrusted data is not interpolated into `su -c`.
- [ ] Android and Termux binaries are resolved intentionally.

## Filesystem and recovery

- [ ] Paths use `Path`.
- [ ] Caller working directory is not assumed.
- [ ] Destructive targets are resolved and contained.
- [ ] String prefix is not the sole containment check.
- [ ] `ls` output is not parsed.
- [ ] Encodings are explicit.
- [ ] Important files use atomic replacement where supported.
- [ ] Temporary resources are securely created.
- [ ] Context managers own resources.
- [ ] Cleanup tolerates partial initialisation.
- [ ] Cleanup cannot obscure the primary exception.
- [ ] Essential correctness does not depend on `atexit`.
- [ ] SIGKILL and Android forced termination are assumed possible.
- [ ] Checkpoints are atomic and written only after validated stages.
- [ ] Operations are idempotent or transactional.
- [ ] The next run can identify incomplete state.

## Resource use and diagnostics

- [ ] Concurrency is bounded.
- [ ] Future and worker exceptions are consumed.
- [ ] Inputs, output, archives, logs, and memory use are bounded.
- [ ] Low-storage failure preserves the previous valid result.
- [ ] Archive paths and expanded sizes are validated.
- [ ] Logs do not contain secrets.
- [ ] stdout remains clean for machine-readable output.
- [ ] Long stages show meaningful progress.
- [ ] Final status and exit code are explicit.
- [ ] Required output is validated before success is reported.
- [ ] The script can be rerun safely after partial completion.
- [ ] `python -m py_compile` and automated tests pass.

---

# 34. Final rules for agents

When generating or revising a Python script for Termux:

1. Inspect before modifying.
2. Make one logical change at a time.
3. Treat optional failures as warnings, not fatal errors.
4. Treat unsafe ambiguity as a hard stop.
5. Do not catch broadly merely to keep going.
6. Do not add retries unless the failure is genuinely transient.
7. Do not leave any uncertain wait unbounded.
8. Do not capture unbounded output into memory.
9. Do not overwrite important files in place.
10. Do not keep authoritative working state on shared storage.
11. Do not rely on cleanup after SIGKILL.
12. Do not run the entire script as root without necessity.
13. Do not interpolate untrusted data into shell commands.
14. Do not claim success until the required result is validated.
15. Always make rerun behaviour explicit and safe.

The final engineering standard is:

> **Bound every uncertain wait. Preserve the last valid state. Catch only what you understand. Keep authoritative work in private Termux storage. Assume Android can terminate the process at any point.**
