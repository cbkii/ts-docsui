#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
import zipfile
from pathlib import Path

FIXED_DATE = (2026, 1, 1, 0, 0, 0)
EXCLUDE_NAMES = {".git", ".github", "dist", "__pycache__"}
EXECUTE_SUFFIXES = {".sh"}
EXECUTE_NAMES = {"update-binary"}


def parse_prop(path: Path) -> dict[str, str]:
    props: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            props[key.strip()] = value.strip()
    return props


def safe_filename(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-._") or "module"


def should_exclude(path: Path, module_dir: Path) -> bool:
    rel = path.relative_to(module_dir)
    return any(part in EXCLUDE_NAMES for part in rel.parts)


def zip_mode(path: Path) -> int:
    if path.is_dir():
        return stat.S_IFDIR | 0o755
    if path.suffix in EXECUTE_SUFFIXES or path.name in EXECUTE_NAMES:
        return stat.S_IFREG | 0o755
    return stat.S_IFREG | 0o644


def add_file(zf: zipfile.ZipFile, path: Path, arcname: str) -> None:
    info = zipfile.ZipInfo(arcname, FIXED_DATE)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = zip_mode(path) << 16
    with path.open("rb") as fh:
        zf.writestr(info, fh.read())


def add_dir(zf: zipfile.ZipFile, arcname: str) -> None:
    if not arcname.endswith("/"):
        arcname += "/"
    info = zipfile.ZipInfo(arcname, FIXED_DATE)
    info.external_attr = (stat.S_IFDIR | 0o755) << 16
    zf.writestr(info, b"")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build an installable Magisk module zip.")
    parser.add_argument("--module-dir", type=Path, default=Path("module"))
    parser.add_argument("--out-dir", type=Path, default=Path("dist"))
    parser.add_argument("--github-output", type=Path, default=None)
    args = parser.parse_args(argv)

    module_dir = args.module_dir.resolve()
    out_dir = args.out_dir.resolve()
    module_prop = module_dir / "module.prop"
    if not module_prop.is_file():
        print(f"ERROR: module.prop missing: {module_prop}", file=sys.stderr)
        return 1

    props = parse_prop(module_prop)
    module_id = props.get("id", "module")
    version = props.get("version", "v0.0.0")
    version_code = props.get("versionCode", "0")
    if not version_code.isdigit():
        print(f"ERROR: versionCode must contain only digits: {version_code}", file=sys.stderr)
        return 1

    out_dir.mkdir(parents=True, exist_ok=True)
    zip_name = f"{safe_filename(module_id)}-{safe_filename(version)}-{safe_filename(version_code)}.zip"
    zip_path = out_dir / zip_name
    temp_path = out_dir / f".{zip_name}.tmp"

    if temp_path.exists():
        temp_path.unlink()

    entries: list[Path] = []
    for path in module_dir.rglob("*"):
        if should_exclude(path, module_dir):
            continue
        entries.append(path)
    entries.sort(key=lambda p: p.relative_to(module_dir).as_posix())

    with zipfile.ZipFile(temp_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        # Add directories first for cleaner listings.
        for path in entries:
            if path.is_dir():
                add_dir(zf, path.relative_to(module_dir).as_posix())
        for path in entries:
            if path.is_file():
                rel = path.relative_to(module_dir).as_posix()
                add_file(zf, path, rel)

    os.replace(temp_path, zip_path)
    digest = sha256(zip_path)
    sha_path = zip_path.with_suffix(zip_path.suffix + ".sha256")
    sha_path.write_text(f"{digest}  {zip_name}\n", encoding="utf-8", newline="\n")

    result = {
        "module_id": module_id,
        "version": version,
        "version_code": version_code,
        "version_code_number": int(version_code, 10),
        "zip_name": zip_name,
        "zip_path": str(zip_path),
        "sha256": digest,
        "sha256_path": str(sha_path),
    }
    print(json.dumps(result, indent=2, sort_keys=True))

    output_path = args.github_output or (Path(os.environ["GITHUB_OUTPUT"]) if "GITHUB_OUTPUT" in os.environ else None)
    if output_path:
        with output_path.open("a", encoding="utf-8") as fh:
            for key, value in result.items():
                fh.write(f"{key}={value}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
