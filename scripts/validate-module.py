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
]
EXECUTABLE_SCRIPTS = [
    "customize.sh",
    "service.sh",
    "post-fs-data.sh",
    "uninstall.sh",
    "action.sh",
    "tools/rootfs-helper.sh",
    "tools/ts18-saf-deepdiag.sh",
]
FORBIDDEN_FILES = [
    "system/priv-app/ExternalStorageProvider/ExternalStorageProvider.apk",
    "system/priv-app/TS18LocalDocumentsProvider/TS18LocalDocumentsProvider.apk",
    "system/etc/sysconfig/ts18-documentsui-saf.xml",
    "tools/ts18-saf-diagnose.sh",
    "tools/ts18-saf-launch.sh",
    "tools/ts18-saf-evidence-v2.sh",
    "tools/ts18-saf-evidence-common.sh",
    "tools/ts18-saf-evidence-remount.sh",
]
VERSION_RE = re.compile(r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
FINAL_UPDATE_JSON = "https://github.com/cbkii/ts-docsui/releases/latest/download/update.json"


def parse_prop(path: Path) -> dict[str, str]:
    props: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8", errors="strict").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"Malformed module.prop line: {raw!r}")
        key, value = line.split("=", 1)
        key = key.strip()
        if key in props:
            raise ValueError(f"Duplicate module.prop key: {key}")
        props[key] = value.strip()
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
    parser = argparse.ArgumentParser(description="Validate the ts-docsui source module directory.")
    parser.add_argument("--module-dir", type=Path, default=Path("module"))
    parser.add_argument("--expected-version", default="")
    parser.add_argument("--expected-version-code", default="")
    args = parser.parse_args(argv)
    module_dir = args.module_dir.resolve()
    if not module_dir.is_dir():
        return fail(f"module directory not found: {module_dir}")
    missing = [name for name in REQUIRED_FILES if not (module_dir / name).is_file()]
    if missing:
        return fail("missing required source files: " + ", ".join(missing))
    present = [name for name in FORBIDDEN_FILES if (module_dir / name).exists()]
    if present:
        return fail("obsolete or forbidden payloads remain: " + ", ".join(present))
    if (module_dir / "install.sh").exists():
        return fail("Magisk modules must not include install.sh")
    updater = (module_dir / "META-INF/com/google/android/updater-script").read_text(
        encoding="utf-8", errors="replace"
    ).strip()
    if updater != "#MAGISK":
        return fail("META-INF/com/google/android/updater-script must contain only #MAGISK")
    try:
        props = parse_prop(module_dir / "module.prop")
    except ValueError as exc:
        return fail(str(exc))
    for key in ("id", "name", "version", "versionCode", "author", "description", "updateJson"):
        if not props.get(key):
            return fail(f"module.prop missing required key: {key}")
    if props["id"] != "ts-docsui":
        return fail(f"module id must be ts-docsui, found {props['id']!r}")
    if props["updateJson"] != FINAL_UPDATE_JSON:
        return fail(f"module updateJson must use the stable release channel: {FINAL_UPDATE_JSON}")
    if not VERSION_RE.fullmatch(props["version"]):
        return fail(f"version must use vMAJOR.MINOR.PATCH: {props['version']}")
    if not props["versionCode"].isdigit() or int(props["versionCode"]) < 1:
        return fail(f"versionCode must be a positive integer: {props['versionCode']!r}")
    if args.expected_version and props["version"] != args.expected_version:
        return fail(f"expected version {args.expected_version}, found {props['version']}")
    if args.expected_version_code and props["versionCode"] != args.expected_version_code:
        return fail(f"expected versionCode {args.expected_version_code}, found {props['versionCode']}")
    for apk_rel, minimum in (
        ("system/priv-app/DocumentsUI/DocumentsUI.apk", 1024 * 1024),
        ("system/priv-app/TS18RootFileProvider/TS18RootFileProvider.apk", 10_000),
    ):
        error = validate_apk(module_dir / apk_rel, minimum)
        if error:
            return fail(error)
    for rel in EXECUTABLE_SCRIPTS:
        path = module_dir / rel
        if not path.read_bytes()[:64].startswith(b"#!"):
            return fail(f"script missing shebang: {rel}")
        text = path.read_text(encoding="utf-8", errors="replace")
        if re.search(r"(^|[\s\"'])/(tmp|cache|data/local/tmp)(/|[\s\"']|$)", text):
            return fail(f"script uses a forbidden temporary root: {rel}")
    diagnostic = (module_dir / "tools/ts18-saf-deepdiag.sh").read_text(encoding="utf-8")
    if "/storage/emulated/0/Download/ts-docsui/diagnostics" not in diagnostic:
        return fail("diagnostics must work and export under Download/ts-docsui/diagnostics")
    if "/data/adb/ts-docsui/diagnostics" in diagnostic:
        return fail("diagnostics must not stage under /data/adb")
    service = (module_dir / "service.sh").read_text(encoding="utf-8")
    if "OUT=/storage/emulated/0/Download/ts-docsui" not in service or "LOG=/dev/null" not in service:
        return fail("runtime logs must use Download/ts-docsui and fail closed to /dev/null")
    if re.search(r"/data/adb/(?:ts-docsui|ts18-documentsui-saf)/(?:logs|diagnostics)", service):
        return fail("runtime service must not store logs or diagnostics under /data/adb")
    print(f"OK module ts-docsui {props['version']} ({props['versionCode']}) at {module_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
