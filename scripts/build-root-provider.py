#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fail(message: str) -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Build the signed TS18 root DocumentsProvider and place it in the Magisk module."
    )
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--gradle", default=os.environ.get("GRADLE_CMD", "gradle"))
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args(argv)

    repo = args.repo_root.resolve()
    encoded_key = repo / "rootprovider/keystore/tsdocsui-root-provider.jks.b64"
    key = repo / "rootprovider/keystore/tsdocsui-root-provider.jks"
    output_apk = repo / "module/system/priv-app/TS18RootFileProvider/TS18RootFileProvider.apk"
    baseline_apk = repo / ".build/provider-before-build.apk"

    if not encoded_key.is_file():
        return fail(f"encoded signing key is missing: {encoded_key}")

    try:
        encoded_text = "".join(encoded_key.read_text(encoding="ascii").split())
        key_bytes = base64.b64decode(encoded_text, validate=True)
    except (ValueError, UnicodeError) as exc:
        return fail(f"encoded signing key is invalid: {exc}")

    if len(key_bytes) < 1_024:
        return fail(f"decoded signing key looks too small: {len(key_bytes)} bytes")

    key.parent.mkdir(parents=True, exist_ok=True)
    key.write_bytes(key_bytes)
    os.chmod(key, 0o600)

    if output_apk.is_file():
        baseline_apk.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(output_apk, baseline_apk)
        print(f"BASELINE provider APK: {baseline_apk}")
        print(f"baseline_sha256={sha256(baseline_apk)}")
    else:
        baseline_apk.unlink(missing_ok=True)

    gradle = shutil.which(args.gradle) if os.path.sep not in args.gradle else args.gradle
    if not gradle:
        return fail(f"Gradle command is unavailable: {args.gradle}")

    command = [
        str(gradle),
        "--no-daemon",
        "--console=plain",
        ":rootprovider:clean",
        ":rootprovider:lintRelease",
        ":rootprovider:assembleRelease",
    ]
    print("RUN:", " ".join(command), flush=True)
    try:
        completed = subprocess.run(command, cwd=repo, timeout=args.timeout, check=False)
    except subprocess.TimeoutExpired:
        return fail(f"Android build exceeded {args.timeout} seconds")

    if completed.returncode != 0:
        return fail(f"Android build failed with status {completed.returncode}")

    candidates = sorted((repo / "rootprovider/build/outputs/apk/release").glob("*.apk"))
    if not candidates:
        return fail("release APK was not produced")

    built_apk = candidates[0]
    output_apk.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(built_apk, output_apk)

    if output_apk.stat().st_size < 10_000:
        return fail(f"provider APK looks too small: {output_apk.stat().st_size} bytes")

    try:
        with zipfile.ZipFile(output_apk) as archive:
            names = set(archive.namelist())
            if "AndroidManifest.xml" not in names or "classes.dex" not in names:
                return fail("provider APK is missing AndroidManifest.xml or classes.dex")
            bad = archive.testzip()
            if bad:
                return fail(f"provider APK has a corrupt member: {bad}")
    except zipfile.BadZipFile as exc:
        return fail(f"provider APK is invalid: {exc}")

    print(f"OK provider APK: {output_apk}")
    print(f"size={output_apk.stat().st_size}")
    print(f"sha256={sha256(output_apk)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
