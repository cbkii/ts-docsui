#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    from scripts.release_version import parse_properties, parse_semver
except ModuleNotFoundError:
    from release_version import parse_properties, parse_semver


def substitute_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise ValueError(f"Expected one {label} version marker, found {count}")
    return updated


def synced_text(path: Path, text: str, version: str, version_code: str) -> str:
    if path.as_posix().endswith("module/service.sh"):
        text = substitute_once(
            text,
            r"^LOG=\$LOGDIR/service-v[0-9]+\.log$",
            f"LOG=$LOGDIR/service-v{version_code}.log",
            "service log",
        )
        text = substitute_once(
            text,
            r'^  desired="v[0-9]+\.[0-9]+\.[0-9]+:\$show:\$config_hash"$',
            f'  desired="{version}:$show:$config_hash"',
            "service applied-state",
        )
        text = substitute_once(
            text,
            r'^log "===== TS18 Full File Picker v[0-9]+\.[0-9]+\.[0-9]+ start ====="$',
            f'log "===== TS18 Full File Picker {version} start ====="',
            "service heading",
        )
        return text
    raise ValueError(f"Unsupported runtime file: {path}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Synchronize unavoidable runtime version markers from module/module.prop."
    )
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args(argv)
    if args.check == args.apply:
        parser.error("choose exactly one of --check or --apply")

    repo = args.repo_root.resolve()
    try:
        props = parse_properties(repo / "module/module.prop")
        version = parse_semver(props.get("version", ""), field="module version").tag
        version_code = props.get("versionCode", "")
        if not version_code.isdigit():
            raise ValueError("module versionCode must be numeric")

        changed: list[str] = []
        for relative in ("module/service.sh",):
            path = repo / relative
            original = path.read_text(encoding="utf-8", errors="strict")
            updated = synced_text(path, original, version, version_code)
            if updated != original:
                changed.append(relative)
                if args.apply:
                    path.write_text(updated, encoding="utf-8", newline="\n")

        if args.check and changed:
            raise ValueError("runtime version markers are stale: " + ", ".join(changed))
        print("OK runtime version markers" + (f" updated: {', '.join(changed)}" if changed else ""))
        return 0
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
