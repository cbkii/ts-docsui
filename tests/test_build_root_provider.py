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
    def test_signer_digest_accepts_apksigner_output_on_stderr(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apksigner = root / "apksigner"
            apksigner.write_text(
                "#!/bin/sh\n"
                "printf '  Signer #1 certificate SHA-256 digest: AABBCCDD\\r\\n' >&2\n",
                encoding="utf-8",
            )
            apksigner.chmod(0o755)
            apk = root / "provider.apk"
            apk.write_bytes(b"fixture")
            self.assertEqual(MODULE.signer_digest(str(apksigner), apk), "aabbccdd")

    def test_signer_digest_failure_preserves_bounded_tool_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apksigner = root / "apksigner"
            apksigner.write_text(
                "#!/bin/sh\nprintf 'certificate output unavailable\\n' >&2\n",
                encoding="utf-8",
            )
            apksigner.chmod(0o755)
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
