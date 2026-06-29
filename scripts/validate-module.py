#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REQUIRED_FILES = [
    "module.prop",
    "customize.sh",
    "service.sh",
    "post-fs-data.sh",
    "uninstall.sh",
    "action.sh",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
    "system/priv-app/DocumentsUI/DocumentsUI.apk",
]

EXECUTABLE_SCRIPTS = [
    "customize.sh",
    "service.sh",
    "post-fs-data.sh",
    "uninstall.sh",
    "action.sh",
    "tools/ts18-saf-deepdiag.sh",
    "tools/ts18-saf-diagnose.sh",
    "tools/ts18-saf-launch.sh",
]

ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9._-]+$")
VCODE_RE = re.compile(r"^[0-9]+$")


def parse_prop(path: Path) -> dict[str, str]:
    props: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"Malformed module.prop line: {raw!r}")
        key, value = line.split("=", 1)
        props[key.strip()] = value.strip()
    return props


def fail(message: str) -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate a Magisk module directory.")
    parser.add_argument("--module-dir", type=Path, default=Path("module"))
    parser.add_argument("--expected-version", default="")
    parser.add_argument("--expected-version-code", default="")
    args = parser.parse_args(argv)

    module_dir = args.module_dir.resolve()
    if not module_dir.is_dir():
        return fail(f"module directory not found: {module_dir}")

    missing = [name for name in REQUIRED_FILES if not (module_dir / name).is_file()]
    if missing:
        return fail("missing required module files: " + ", ".join(missing))

    if (module_dir / "install.sh").exists():
        return fail("Magisk modules must not include install.sh")

    updater = (module_dir / "META-INF/com/google/android/updater-script").read_text(
        encoding="utf-8", errors="replace"
    ).strip()
    if updater != "#MAGISK":
        return fail("META-INF/com/google/android/updater-script must contain only #MAGISK")

    props = parse_prop(module_dir / "module.prop")
    for key in ("id", "name", "version", "versionCode", "author", "description"):
        if not props.get(key):
            return fail(f"module.prop missing required key: {key}")

    if not ID_RE.fullmatch(props["id"]):
        return fail(f"module id is not Magisk-compatible: {props['id']}")

    if not VCODE_RE.fullmatch(props["versionCode"]):
        return fail(f"versionCode must be an integer string: {props['versionCode']}")

    # Parse as base 10 so 080 is valid and not treated as octal.
    try:
        int(props["versionCode"], 10)
    except ValueError:
        return fail(f"versionCode is not base-10 parseable: {props['versionCode']}")

    if args.expected_version and props["version"] != args.expected_version:
        return fail(f"expected version {args.expected_version}, found {props['version']}")

    if args.expected_version_code and props["versionCode"] != args.expected_version_code:
        return fail(
            f"expected versionCode {args.expected_version_code}, found {props['versionCode']}"
        )

    apk = module_dir / "system/priv-app/DocumentsUI/DocumentsUI.apk"
    if apk.stat().st_size <= 1024 * 1024:
        return fail(f"DocumentsUI.apk looks too small: {apk.stat().st_size} bytes")

    for rel in EXECUTABLE_SCRIPTS:
        path = module_dir / rel
        if path.exists():
            first = path.read_bytes()[:64]
            if not first.startswith(b"#!"):
                return fail(f"script missing shebang: {rel}")

    print(
        f"OK module {props['id']} {props['version']} ({props['versionCode']}) at {module_dir}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
