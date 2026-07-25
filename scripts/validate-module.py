#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path

REQUIRED_FILES = [
    "module.prop",
    "config.default",
    "customize.sh",
    "service.sh",
    "post-fs-data.sh",
    "uninstall.sh",
    "action.sh",
    "README.md",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
    "system/priv-app/DocumentsUI/DocumentsUI.apk",
    "system/priv-app/TS18RootFileProvider/TS18RootFileProvider.apk",
    "tools/rootfs-helper.sh",
    "tools/ts18-saf-deepdiag.sh",
    "tools/ts18-saf-diagnose.sh",
    "tools/ts18-saf-launch.sh",
]

EXECUTABLE_SCRIPTS = [
    "customize.sh",
    "service.sh",
    "post-fs-data.sh",
    "uninstall.sh",
    "action.sh",
    "tools/rootfs-helper.sh",
    "tools/ts18-saf-deepdiag.sh",
    "tools/ts18-saf-diagnose.sh",
    "tools/ts18-saf-launch.sh",
]

ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9._-]+$")
VERSION_RE = re.compile(r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
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


def validate_apk(path: Path, minimum_size: int) -> str | None:
    if path.stat().st_size <= minimum_size:
        return f"APK looks too small: {path} ({path.stat().st_size} bytes)"
    try:
        with zipfile.ZipFile(path) as archive:
            names = set(archive.namelist())
            for required in ("AndroidManifest.xml", "classes.dex"):
                if required not in names:
                    return f"APK is missing {required}: {path}"
            bad = archive.testzip()
            if bad:
                return f"APK contains a corrupt member {bad}: {path}"
    except zipfile.BadZipFile as exc:
        return f"APK is invalid: {path}: {exc}"
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate the TS18 Magisk module directory.")
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
    if props["id"] != "ts18_documentsui_saf_full":
        return fail("module id must remain ts18_documentsui_saf_full to upgrade existing installs")
    if not VERSION_RE.fullmatch(props["version"]):
        return fail(f"version must use vMAJOR.MINOR.PATCH: {props['version']}")
    if not VCODE_RE.fullmatch(props["versionCode"]):
        return fail(f"versionCode must be an integer string: {props['versionCode']}")
    if int(props["versionCode"], 10) < 1:
        return fail("versionCode must be positive")

    if args.expected_version and props["version"] != args.expected_version:
        return fail(f"expected version {args.expected_version}, found {props['version']}")
    if args.expected_version_code and props["versionCode"] != args.expected_version_code:
        return fail(
            f"expected versionCode {args.expected_version_code}, found {props['versionCode']}"
        )

    for apk_rel, minimum in (
        ("system/priv-app/DocumentsUI/DocumentsUI.apk", 1024 * 1024),
        ("system/priv-app/TS18RootFileProvider/TS18RootFileProvider.apk", 10_000),
    ):
        error = validate_apk(module_dir / apk_rel, minimum)
        if error:
            return fail(error)

    forbidden_payloads = [
        "system/priv-app/ExternalStorageProvider/ExternalStorageProvider.apk",
        "system/priv-app/TS18LocalDocumentsProvider/TS18LocalDocumentsProvider.apk",
    ]
    present = [path for path in forbidden_payloads if (module_dir / path).exists()]
    if present:
        return fail("module must not overlay known-problem provider APKs: " + ", ".join(present))

    for rel in EXECUTABLE_SCRIPTS:
        path = module_dir / rel
        first = path.read_bytes()[:64]
        if not first.startswith(b"#!"):
            return fail(f"script missing shebang: {rel}")
        text = path.read_text(encoding="utf-8", errors="replace")
        if re.search(r"(^|[\s\"'])/(tmp|cache|data/local/tmp)(/|[\s\"']|$)", text):
            return fail(f"script uses a forbidden temporary root: {rel}")

    print(
        f"OK module {props['id']} {props['version']} ({props['versionCode']}) at {module_dir}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
