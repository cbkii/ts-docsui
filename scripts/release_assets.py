#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import tempfile
import zipfile
from pathlib import Path
from typing import Any

try:
    from scripts.release_version import parse_properties, parse_properties_text, parse_semver
except ModuleNotFoundError:
    from release_version import parse_properties, parse_properties_text, parse_semver

SHA256_RE = re.compile(r"^([0-9a-fA-F]{64})[ \t]+[*]?([^\r\n]+)$")
REQUIRED_ZIP_ENTRIES = {
    "module.prop",
    "customize.sh",
    "system/priv-app/DocumentsUI/DocumentsUI.apk",
    "system/priv-app/TS18RootFileProvider/TS18RootFileProvider.apk",
    "tools/rootfs-helper.sh",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_filename(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-._") or "module"


def expected_zip_name(props: dict[str, str]) -> str:
    return (
        f"{safe_filename(props['id'])}-{safe_filename(props['version'])}-"
        f"{safe_filename(props['versionCode'])}.zip"
    )


def parse_checksum_file(path: Path) -> tuple[str, str]:
    lines = [line for line in path.read_text(encoding="utf-8", errors="strict").splitlines() if line]
    if len(lines) != 1:
        raise ValueError(f"checksum file must contain exactly one non-empty line: {path}")
    match = SHA256_RE.fullmatch(lines[0])
    if not match:
        raise ValueError(f"invalid SHA-256 checksum line in {path}: {lines[0]!r}")
    return match.group(1).lower(), match.group(2)


def read_zip_module_properties(zip_path: Path) -> tuple[dict[str, str], set[str]]:
    try:
        with zipfile.ZipFile(zip_path) as archive:
            bad = archive.testzip()
            if bad:
                raise ValueError(f"corrupt ZIP member: {bad}")
            names = set(archive.namelist())
            missing = REQUIRED_ZIP_ENTRIES - names
            if missing:
                raise ValueError(f"missing ZIP entries: {sorted(missing)}")
            compressed = [item.filename for item in archive.infolist() if item.compress_type != zipfile.ZIP_STORED]
            if compressed:
                raise ValueError(f"non-STORE ZIP entries: {compressed[:10]}")
            text = archive.read("module.prop").decode("utf-8", errors="strict")
    except zipfile.BadZipFile as exc:
        raise ValueError(f"invalid ZIP archive: {zip_path}") from exc

    return parse_properties_text(text, source=f"{zip_path}!/module.prop"), names


def build_payload(*, props: dict[str, str], repository: str, tag: str, zip_name: str) -> dict[str, Any]:
    return {
        "version": props["version"],
        "versionCode": int(props["versionCode"], 10),
        "zipUrl": f"https://github.com/{repository}/releases/download/{tag}/{zip_name}",
        "changelog": f"https://github.com/{repository}/releases/tag/{tag}",
    }


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    current_mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_path, current_mode)
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def validate_release_assets(
    *,
    module_dir: Path,
    repository: str,
    tag: str,
    zip_path: Path,
    checksum_path: Path,
) -> tuple[dict[str, Any], str]:
    module_prop = module_dir / "module.prop"
    props = parse_properties(module_prop)
    required = ("id", "version", "versionCode")
    missing_props = [key for key in required if not props.get(key)]
    if missing_props:
        raise ValueError(f"module.prop is missing required properties: {missing_props}")

    canonical_tag = parse_semver(tag, field="tag").tag
    module_tag = parse_semver(props["version"], field="module version").tag
    if canonical_tag != tag:
        raise ValueError(f"release tag must be canonical with a leading v: {tag!r}")
    if module_tag != tag:
        raise ValueError(f"module version {module_tag} does not match release tag {tag}")
    if not props["versionCode"].isdigit() or int(props["versionCode"], 10) < 1:
        raise ValueError(f"module versionCode must be a positive integer: {props['versionCode']!r}")

    expected_name = expected_zip_name(props)
    if zip_path.name != expected_name:
        raise ValueError(f"ZIP name {zip_path.name!r} does not match expected {expected_name!r}")
    if not zip_path.is_file():
        raise ValueError(f"release ZIP is missing: {zip_path}")
    if not checksum_path.is_file():
        raise ValueError(f"checksum file is missing: {checksum_path}")

    expected_digest, checksum_name = parse_checksum_file(checksum_path)
    if checksum_name != zip_path.name:
        raise ValueError(
            f"checksum names {checksum_name!r}, expected ZIP basename {zip_path.name!r}"
        )
    actual_digest = sha256(zip_path)
    if actual_digest != expected_digest:
        raise ValueError(
            f"ZIP SHA-256 mismatch: checksum has {expected_digest}, actual is {actual_digest}"
        )

    embedded_props, _ = read_zip_module_properties(zip_path)
    for key in required:
        if embedded_props.get(key) != props[key]:
            raise ValueError(
                f"ZIP module.prop {key}={embedded_props.get(key)!r} does not match "
                f"source {key}={props[key]!r}"
            )

    payload = build_payload(props=props, repository=repository, tag=tag, zip_name=zip_path.name)
    return payload, actual_digest
