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
DEBUG_ONLY = {"action.sh", "tools/ts18-saf-deepdiag.sh"}
DEBUG_REQUIRED = DEBUG_ONLY | {"README.md"}
FINAL_EXCLUDE = DEBUG_REQUIRED
UPDATE_JSON_URLS = {
    "final": "https://github.com/cbkii/ts-docsui/releases/latest/download/update.json",
    "debug": "https://github.com/cbkii/ts-docsui/releases/latest/download/update-debug.json",
}


def parse_prop_text(text: str) -> dict[str, str]:
    props: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            props[key.strip()] = value.strip()
    return props


def parse_prop(path: Path) -> dict[str, str]:
    return parse_prop_text(path.read_text(encoding="utf-8", errors="strict"))


def should_exclude(path: Path, module_dir: Path, variant: str) -> bool:
    rel = path.relative_to(module_dir)
    if any(part in EXCLUDE_NAMES for part in rel.parts):
        return True
    return variant == "final" and rel.as_posix() in FINAL_EXCLUDE


def zip_mode(path: Path) -> int:
    if path.suffix in EXECUTE_SUFFIXES or path.name in EXECUTE_NAMES:
        return stat.S_IFREG | 0o755
    return stat.S_IFREG | 0o644


def add_bytes(archive: zipfile.ZipFile, path: Path, arcname: str, payload: bytes) -> None:
    info = zipfile.ZipInfo(arcname, FIXED_DATE)
    info.compress_type = zipfile.ZIP_STORED
    info.create_system = 3
    info.external_attr = zip_mode(path) << 16
    info.extra = b""
    archive.writestr(info, payload)


def variant_module_prop(path: Path, variant: str) -> bytes:
    text = path.read_text(encoding="utf-8", errors="strict")
    updated, count = re.subn(
        r"(?m)^updateJson=.*$",
        f"updateJson={UPDATE_JSON_URLS[variant]}",
        text,
    )
    if count != 1:
        raise ValueError("module.prop must contain exactly one updateJson entry")
    return (updated.rstrip("\n") + "\n").encode("utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def expected_name(variant: str, version_code: str) -> str:
    prefix = "ts-docsui-debug" if variant == "debug" else "ts-docsui"
    return f"{prefix}-v{version_code}.zip"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build one deterministic ts-docsui Magisk ZIP variant.")
    parser.add_argument("--module-dir", type=Path, default=Path("module"))
    parser.add_argument("--out-dir", type=Path, default=Path("dist"))
    parser.add_argument("--variant", choices=("final", "debug"), required=True)
    parser.add_argument("--github-output", type=Path, default=None)
    args = parser.parse_args(argv)

    module_dir = args.module_dir.resolve()
    out_dir = args.out_dir.resolve()
    module_prop = module_dir / "module.prop"
    if not module_prop.is_file():
        print(f"ERROR: module.prop missing: {module_prop}", file=sys.stderr)
        return 1

    props = parse_prop(module_prop)
    module_id = props.get("id", "")
    version = props.get("version", "")
    version_code = props.get("versionCode", "")
    if module_id != "ts-docsui":
        print(f"ERROR: module id must be ts-docsui, found {module_id!r}", file=sys.stderr)
        return 1
    if not re.fullmatch(r"v\d+\.\d+\.\d+", version):
        print(f"ERROR: invalid module version: {version!r}", file=sys.stderr)
        return 1
    if not version_code.isdigit() or int(version_code) < 1:
        print(f"ERROR: versionCode must be a positive integer: {version_code!r}", file=sys.stderr)
        return 1
    if props.get("updateJson") != UPDATE_JSON_URLS["final"]:
        print("ERROR: source module.prop must use the stable final update channel", file=sys.stderr)
        return 1
    for required in DEBUG_REQUIRED:
        if not (module_dir / required).is_file():
            print(f"ERROR: source module is missing debug payload: {required}", file=sys.stderr)
            return 1

    out_dir.mkdir(parents=True, exist_ok=True)
    zip_name = expected_name(args.variant, version_code)
    zip_path = out_dir / zip_name
    temp_path = out_dir / f".{zip_name}.new"
    temp_path.unlink(missing_ok=True)

    files = sorted(
        (
            path
            for path in module_dir.rglob("*")
            if path.is_file() and not should_exclude(path, module_dir, args.variant)
        ),
        key=lambda path: path.relative_to(module_dir).as_posix(),
    )

    try:
        with zipfile.ZipFile(temp_path, "w", compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
            for path in files:
                arcname = path.relative_to(module_dir).as_posix()
                payload = variant_module_prop(path, args.variant) if arcname == "module.prop" else path.read_bytes()
                add_bytes(archive, path, arcname, payload)
        with zipfile.ZipFile(temp_path, allowZip64=False) as archive:
            bad = archive.testzip()
            if bad:
                raise RuntimeError(f"corrupt ZIP member: {bad}")
            names = set(archive.namelist())
            if any(info.compress_type != zipfile.ZIP_STORED for info in archive.infolist()):
                raise RuntimeError("ZIP contains a compressed entry")
            if args.variant == "final" and FINAL_EXCLUDE & names:
                raise RuntimeError(f"final ZIP contains non-runtime entries: {sorted(FINAL_EXCLUDE & names)}")
            if args.variant == "debug" and not DEBUG_REQUIRED <= names:
                raise RuntimeError(f"debug ZIP is missing entries: {sorted(DEBUG_REQUIRED - names)}")
            embedded = parse_prop_text(archive.read("module.prop").decode("utf-8", errors="strict"))
            expected_update = UPDATE_JSON_URLS[args.variant]
            if embedded.get("updateJson") != expected_update:
                raise RuntimeError(f"{args.variant} ZIP has the wrong updateJson channel")
        os.replace(temp_path, zip_path)
    except Exception as exc:
        temp_path.unlink(missing_ok=True)
        print(f"ERROR: failed to build {args.variant} module ZIP: {exc}", file=sys.stderr)
        return 1

    digest = sha256(zip_path)
    sha_path = zip_path.with_suffix(zip_path.suffix + ".sha256")
    sha_path.write_text(f"{digest}  {zip_name}\n", encoding="utf-8", newline="\n")

    result = {
        "variant": args.variant,
        "module_id": module_id,
        "version": version,
        "version_code": version_code,
        "version_code_number": int(version_code),
        "zip_name": zip_name,
        "zip_path": str(zip_path),
        "sha256": digest,
        "sha256_path": str(sha_path),
        "update_json": UPDATE_JSON_URLS[args.variant],
    }
    print(json.dumps(result, indent=2, sort_keys=True))

    output_path = args.github_output or (Path(os.environ["GITHUB_OUTPUT"]) if "GITHUB_OUTPUT" in os.environ else None)
    if output_path:
        with output_path.open("a", encoding="utf-8") as handle:
            for key, value in result.items():
                handle.write(f"{key}={value}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
