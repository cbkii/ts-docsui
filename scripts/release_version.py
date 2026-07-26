#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

SEMVER_RE = re.compile(r"^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


@dataclass(frozen=True, order=True)
class SemVer:
    major: int
    minor: int
    patch: int

    @property
    def tag(self) -> str:
        return f"v{self.major}.{self.minor}.{self.patch}"

    @property
    def name(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"

    def bump_patch(self) -> "SemVer":
        return SemVer(self.major, self.minor, self.patch + 1)


def parse_semver(value: str, *, field: str = "version") -> SemVer:
    text = value.strip()
    match = SEMVER_RE.fullmatch(text)
    if not match:
        raise ValueError(f"{field} must use MAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH: {value!r}")
    return SemVer(*(int(part, 10) for part in match.groups()))


def parse_properties_text(text: str, *, source: str = "properties") -> dict[str, str]:
    props: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"Malformed property line in {source}: {raw!r}")
        key, value = line.split("=", 1)
        key = key.strip()
        if key in props:
            raise ValueError(f"Duplicate property {key!r} in {source}")
        props[key] = value.strip()
    return props


def parse_properties(path: Path) -> dict[str, str]:
    return parse_properties_text(
        path.read_text(encoding="utf-8", errors="strict"), source=str(path)
    )


def list_git_tags(repo_root: Path) -> list[str]:
    try:
        completed = subprocess.run(
            ["git", "tag", "--list", "v[0-9]*.[0-9]*.[0-9]*"],
            cwd=repo_root,
            check=False,
            text=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("git tag exceeded 30 seconds") from exc
    if completed.returncode != 0:
        raise RuntimeError(f"git tag failed: {completed.stderr.strip()}")
    return [line.strip() for line in completed.stdout.splitlines() if line.strip()]


def valid_tag_versions(tags: Iterable[str]) -> list[SemVer]:
    versions: list[SemVer] = []
    for tag in tags:
        try:
            versions.append(parse_semver(tag, field="tag"))
        except ValueError:
            continue
    return sorted(set(versions))


def resolve_release(
    *,
    current_version: str,
    current_version_code: str,
    tags: Iterable[str],
    requested_version: str = "",
    requested_version_code: str = "",
    allow_lower_version: bool = False,
) -> dict[str, object]:
    current = parse_semver(current_version, field="module version")
    if not current_version_code.isdigit():
        raise ValueError(f"module versionCode must be numeric: {current_version_code!r}")
    current_code = int(current_version_code, 10)
    if current_code < 1:
        raise ValueError("module versionCode must be positive")

    known = valid_tag_versions(tags)
    latest_tag = known[-1] if known else None
    release_floor = max([current, *known])

    requested_version = requested_version.strip()
    if requested_version:
        target = parse_semver(requested_version, field="version_tag")
        source = "explicit"
        if target < release_floor and not allow_lower_version:
            raise ValueError(
                f"requested version {target.tag} is lower than current release floor "
                f"{release_floor.tag}"
            )
    else:
        target = release_floor.bump_patch()
        source = "auto-patch"

    requested_version_code = requested_version_code.strip()
    if requested_version_code:
        if not requested_version_code.isdigit():
            raise ValueError("version_code must contain only digits")
        target_code = int(requested_version_code, 10)
        code_source = "explicit"
    elif requested_version and target == current:
        # An explicit request for the current, still-untagged version is a safe resume path
        # after a prior release run committed metadata but failed before creating its tag.
        target_code = current_code
        code_source = "current-version"
    else:
        target_code = current_code + 1
        code_source = "auto-increment"
    if target_code < 1:
        raise ValueError("resolved versionCode must be positive")

    if not allow_lower_version:
        if target > current and target_code <= current_code:
            raise ValueError(
                f"a newer release requires versionCode greater than {current_code}; "
                f"resolved {target_code}"
            )
        if target == current and target_code < current_code:
            raise ValueError(
                f"version {target.tag} cannot reduce versionCode {current_code} to {target_code}"
            )

    previous = max((version for version in known if version < target), default=None)
    return {
        "release_tag": target.tag,
        "release_version": target.name,
        "release_version_code": str(target_code),
        "version_source": source,
        "version_code_source": code_source,
        "current_version": current.tag,
        "current_version_code": str(current_code),
        "latest_tag": latest_tag.tag if latest_tag else "",
        "previous_tag": previous.tag if previous else "",
        "metadata_change": target.tag != current.tag or target_code != current_code,
        "version_increases": target > current,
        "version_code_increases": target_code > current_code,
    }


def replace_property(text: str, key: str, value: str) -> str:
    pattern = re.compile(rf"(?m)^{re.escape(key)}=.*$")
    updated, count = pattern.subn(f"{key}={value}", text, count=1)
    if count != 1:
        raise ValueError(f"Expected exactly one {key}= line")
    return updated


def atomic_write_text(path: Path, text: str) -> None:
    mode = stat.S_IMODE(path.stat().st_mode)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_path, mode)
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def apply_release(module_prop: Path, release_tag: str, release_version_code: str) -> None:
    text = module_prop.read_text(encoding="utf-8", errors="strict")
    text = replace_property(text, "version", release_tag)
    text = replace_property(text, "versionCode", release_version_code)
    atomic_write_text(module_prop, text.rstrip("\n") + "\n")


def append_github_output(path: Path, values: dict[str, object]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        for key, value in values.items():
            if isinstance(value, bool):
                rendered = "true" if value else "false"
            else:
                rendered = str(value)
            handle.write(f"{key}={rendered}\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Resolve and optionally apply TS18 Magisk release version metadata."
    )
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--module-prop", type=Path, default=Path("module/module.prop"))
    parser.add_argument("--version-tag", default="")
    parser.add_argument("--version-code", default="")
    parser.add_argument("--github-output", type=Path)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--allow-lower-version", action="store_true")
    args = parser.parse_args(argv)

    repo_root = args.repo_root.resolve()
    module_prop = args.module_prop
    if not module_prop.is_absolute():
        module_prop = repo_root / module_prop
    if not module_prop.is_file():
        print(f"ERROR: module.prop not found: {module_prop}", file=sys.stderr)
        return 1

    try:
        props = parse_properties(module_prop)
        result = resolve_release(
            current_version=props.get("version", ""),
            current_version_code=props.get("versionCode", ""),
            tags=list_git_tags(repo_root),
            requested_version=args.version_tag,
            requested_version_code=args.version_code,
            allow_lower_version=args.allow_lower_version,
        )
        if args.apply:
            apply_release(
                module_prop,
                str(result["release_tag"]),
                str(result["release_version_code"]),
            )
        output_path = args.github_output
        if output_path is None and os.environ.get("GITHUB_OUTPUT"):
            output_path = Path(os.environ["GITHUB_OUTPUT"])
        if output_path is not None:
            append_github_output(output_path, result)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
