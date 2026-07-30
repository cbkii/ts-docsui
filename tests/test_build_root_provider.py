from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "build_root_provider", REPO_ROOT / "scripts/build-root-provider.py"
)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class BuildRootProviderTests(unittest.TestCase):
    def make_apksigner(self, root: Path, output: str, *, status: int = 0) -> Path:
        apksigner = root / "apksigner"
        escaped = output.replace("'", "'\\''")
        apksigner.write_text(
            f"#!/bin/sh\nprintf '%s' '{escaped}' >&2\nexit {status}\n",
            encoding="utf-8",
        )
        apksigner.chmod(0o755)
        return apksigner

    def assert_digest(self, output: str, expected: str = "aabbccdd") -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apksigner = self.make_apksigner(root, output)
            apk = root / "provider.apk"
            apk.write_bytes(b"fixture")
            self.assertEqual(MODULE.signer_digest(str(apksigner), apk), expected)

    def test_signer_digest_accepts_scheme_labelled_output_on_stderr(self) -> None:
        self.assert_digest(
            "V2 Signer: certificate DN: CN=TS18 Root Provider\r\n"
            "V2 Signer: certificate SHA-256 digest: AABBCCDD\r\n"
        )

    def test_signer_digest_accepts_legacy_numbered_output(self) -> None:
        self.assert_digest("Signer #1 certificate SHA-256 digest: AABBCCDD\n")

    def test_signer_digest_accepts_same_digest_across_signature_schemes(self) -> None:
        self.assert_digest(
            "V1 Signer: certificate SHA-256 digest: AABBCCDD\n"
            "V2 Signer: certificate SHA-256 digest: AABBCCDD\n"
        )

    def test_signer_digest_rejects_multiple_distinct_signers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apksigner = self.make_apksigner(
                root,
                "V1 Signer: certificate SHA-256 digest: AABBCCDD\n"
                "V2 Signer: certificate SHA-256 digest: 11223344\n",
            )
            apk = root / "provider.apk"
            apk.write_bytes(b"fixture")
            with self.assertRaisesRegex(RuntimeError, "multiple signer"):
                MODULE.signer_digest(str(apksigner), apk)

    def test_signer_digest_failure_preserves_bounded_tool_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apksigner = self.make_apksigner(root, "certificate output unavailable\n")
            apk = root / "provider.apk"
            apk.write_bytes(b"fixture")
            with self.assertRaisesRegex(RuntimeError, "certificate output unavailable"):
                MODULE.signer_digest(str(apksigner), apk)

    def test_android_tool_falls_back_to_latest_sdk_build_tools(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sdk = Path(directory)
            older = sdk / "build-tools/34.0.0/apksigner"
            latest = sdk / "build-tools/35.0.0/apksigner"
            for path in (older, latest):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("#!/bin/sh\n", encoding="utf-8")
                path.chmod(0o755)
            with mock.patch.object(MODULE.shutil, "which", return_value=None), mock.patch.dict(
                os.environ,
                {"ANDROID_HOME": str(sdk), "ANDROID_SDK_ROOT": ""},
                clear=False,
            ):
                self.assertEqual(MODULE.find_android_tool("apksigner"), str(latest))


if __name__ == "__main__":
    unittest.main()
