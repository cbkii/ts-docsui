#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import struct
import tempfile
import zipfile
from collections.abc import Iterable
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
ZIP64_EXTRA_FIELD_ID = 0x0001
ZIP64_UINT16_SENTINEL = 0xFFFF
ZIP64_UINT32_SENTINEL = 0xFFFFFFFF
LOCAL_FILE_HEADER = struct.Struct("<4s5H3L2H")
END_OF_CENTRAL_DIRECTORY = struct.Struct("<4s4H2LH")
LOCAL_FILE_HEADER_SIGNATURE = b"PK\x03\x04"
END_OF_CENTRAL_DIRECTORY_SIGNATURE = b"PK\x05\x06"
ZIP64_END_OF_CENTRAL_DIRECTORY_LOCATOR_SIGNATURE = b"PK\x06\x07"
MAX_ZIP_COMMENT = 0xFFFF


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
    lines = [
        line
        for line in path.read_text(encoding="utf-8", errors="strict").splitlines()
        if line
    ]
    if len(lines) != 1:
        raise ValueError(f"checksum file must contain exactly one non-empty line: {path}")
    match = SHA256_RE.fullmatch(lines[0])
    if not match:
        raise ValueError(f"invalid SHA-256 checksum line in {path}: {lines[0]!r}")
    return match.group(1).lower(), match.group(2)


def iter_extra_field_ids(extra: bytes, *, source: str) -> Iterable[int]:
    offset = 0
    while offset < len(extra):
        if len(extra) - offset < 4:
            raise ValueError(f"malformed ZIP extra field header in {source}")
        field_id, field_size = struct.unpack_from("<HH", extra, offset)
        offset += 4
        end = offset + field_size
        if end > len(extra):
            raise ValueError(f"malformed ZIP extra field payload in {source}")
        yield field_id
        offset = end


def reject_zip64_end_records(zip_path: Path) -> None:
    tail_size = END_OF_CENTRAL_DIRECTORY.size + MAX_ZIP_COMMENT + 20
    with zip_path.open("rb") as handle:
        handle.seek(0, os.SEEK_END)
        file_size = handle.tell()
        handle.seek(max(0, file_size - tail_size))
        tail = handle.read()

    eocd_offset = tail.rfind(END_OF_CENTRAL_DIRECTORY_SIGNATURE)
    if eocd_offset < 0 or len(tail) - eocd_offset < END_OF_CENTRAL_DIRECTORY.size:
        raise ValueError(f"missing ZIP end-of-central-directory record: {zip_path}")

    (
        _signature,
        disk_number,
        central_directory_disk,
        records_on_disk,
        total_records,
        central_directory_size,
        central_directory_offset,
        comment_length,
    ) = END_OF_CENTRAL_DIRECTORY.unpack_from(tail, eocd_offset)

    if eocd_offset + END_OF_CENTRAL_DIRECTORY.size + comment_length > len(tail):
        raise ValueError(f"truncated ZIP end-of-central-directory record: {zip_path}")

    if (
        disk_number == ZIP64_UINT16_SENTINEL
        or central_directory_disk == ZIP64_UINT16_SENTINEL
        or records_on_disk == ZIP64_UINT16_SENTINEL
        or total_records == ZIP64_UINT16_SENTINEL
        or central_directory_size == ZIP64_UINT32_SENTINEL
        or central_directory_offset == ZIP64_UINT32_SENTINEL
    ):
        raise ValueError(f"ZIP64 end-of-central-directory values are not allowed: {zip_path}")

    locator_offset = eocd_offset - 20
    if (
        locator_offset >= 0
        and tail[locator_offset : locator_offset + 4]
        == ZIP64_END_OF_CENTRAL_DIRECTORY_LOCATOR_SIGNATURE
    ):
        raise ValueError(f"ZIP64 end-of-central-directory locator is not allowed: {zip_path}")


def reject_zip64_members(zip_path: Path, infos: Iterable[zipfile.ZipInfo]) -> None:
    with zip_path.open("rb") as handle:
        for info in infos:
            central_source = f"central directory entry {info.filename!r}"
            if ZIP64_EXTRA_FIELD_ID in iter_extra_field_ids(
                info.extra, source=central_source
            ):
                raise ValueError(f"ZIP64 extra field is not allowed in {central_source}")

            handle.seek(info.header_offset)
            header = handle.read(LOCAL_FILE_HEADER.size)
            if len(header) != LOCAL_FILE_HEADER.size:
                raise ValueError(f"truncated local ZIP header for {info.filename!r}")
            (
                signature,
                _extract_version,
                _flags,
                _compress_type,
                _modified_time,
                _modified_date,
                _crc,
                compressed_size,
                file_size,
                filename_length,
                extra_length,
            ) = LOCAL_FILE_HEADER.unpack(header)
            if signature != LOCAL_FILE_HEADER_SIGNATURE:
                raise ValueError(f"invalid local ZIP header for {info.filename!r}")
            if (
                compressed_size == ZIP64_UINT32_SENTINEL
                or file_size == ZIP64_UINT32_SENTINEL
            ):
                raise ValueError(f"ZIP64 local sizes are not allowed for {info.filename!r}")

            handle.seek(filename_length, os.SEEK_CUR)
            local_extra = handle.read(extra_length)
            if len(local_extra) != extra_length:
                raise ValueError(f"truncated local ZIP extra field for {info.filename!r}")
            local_source = f"local header {info.filename!r}"
            if ZIP64_EXTRA_FIELD_ID in iter_extra_field_ids(
                local_extra, source=local_source
            ):
                raise ValueError(f"ZIP64 extra field is not allowed in {local_source}")


def reject_zip64(zip_path: Path, infos: Iterable[zipfile.ZipInfo]) -> None:
    reject_zip64_end_records(zip_path)
    reject_zip64_members(zip_path, infos)


def read_zip_module_properties(zip_path: Path) -> tuple[dict[str, str], set[str]]:
    try:
        with zipfile.ZipFile(zip_path, allowZip64=False) as archive:
            bad = archive.testzip()
            if bad:
                raise ValueError(f"corrupt ZIP member: {bad}")
            infos = archive.infolist()
            reject_zip64(zip_path, infos)
            names = {item.filename for item in infos}
            missing = REQUIRED_ZIP_ENTRIES - names
            if missing:
                raise ValueError(f"missing ZIP entries: {sorted(missing)}")
            compressed = [
                item.filename
                for item in infos
                if item.compress_type != zipfile.ZIP_STORED
            ]
            if compressed:
                raise ValueError(f"non-STORE ZIP entries: {compressed[:10]}")
            text = archive.read("module.prop").decode("utf-8", errors="strict")
    except (zipfile.BadZipFile, zipfile.LargeZipFile) as exc:
        raise ValueError(f"invalid or ZIP64 archive: {zip_path}") from exc

    return parse_properties_text(text, source=f"{zip_path}!/module.prop"), names


def build_payload(
    *, props: dict[str, str], repository: str, tag: str, zip_name: str
) -> dict[str, Any]:
    return {
        "version": props["version"],
        "versionCode": int(props["versionCode"], 10),
        "zipUrl": f"https://github.com/{repository}/releases/download/{tag}/{zip_name}",
        "changelog": f"https://github.com/{repository}/releases/tag/{tag}",
    }


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    current_mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    fd, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
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
        raise ValueError(
            f"module versionCode must be a positive integer: {props['versionCode']!r}"
        )

    expected_name = expected_zip_name(props)
    if zip_path.name != expected_name:
        raise ValueError(
            f"ZIP name {zip_path.name!r} does not match expected {expected_name!r}"
        )
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

    payload = build_payload(
        props=props, repository=repository, tag=tag, zip_name=zip_path.name
    )
    return payload, actual_digest
