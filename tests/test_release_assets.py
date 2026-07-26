from __future__ import annotations

import hashlib
import tempfile
import unittest
import zipfile
from pathlib import Path

from scripts.release_assets import REQUIRED_ZIP_ENTRIES, validate_release_assets


class ReleaseAssetTests(unittest.TestCase):
    def make_fixture(self, root: Path) -> tuple[Path, Path, Path]:
        module_dir = root / "module"
        module_dir.mkdir()
        module_prop_text = (
            "id=ts18_documentsui_saf_full\n"
            "name=TS18 Full File Picker\n"
            "version=v1.2.3\n"
            "versionCode=123\n"
        )
        (module_dir / "module.prop").write_text(module_prop_text, encoding="utf-8")
        zip_path = root / "ts18_documentsui_saf_full-v1.2.3-123.zip"
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("module.prop", module_prop_text)
            for name in sorted(REQUIRED_ZIP_ENTRIES - {"module.prop"}):
                archive.writestr(name, b"fixture")
        digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
        checksum_path = zip_path.with_suffix(".zip.sha256")
        checksum_path.write_text(f"{digest}  {zip_path.name}\n", encoding="utf-8")
        return module_dir, zip_path, checksum_path

    def test_exact_release_assets_validate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            module_dir, zip_path, checksum_path = self.make_fixture(Path(directory))
            payload, digest = validate_release_assets(
                module_dir=module_dir,
                repository="cbkii/ts-docsui",
                tag="v1.2.3",
                zip_path=zip_path,
                checksum_path=checksum_path,
            )
            self.assertEqual(payload["version"], "v1.2.3")
            self.assertEqual(payload["versionCode"], 123)
            self.assertIn("/v1.2.3/", payload["zipUrl"])
            self.assertEqual(len(digest), 64)

    def test_checksum_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            module_dir, zip_path, checksum_path = self.make_fixture(Path(directory))
            checksum_path.write_text(f"{'0' * 64}  {zip_path.name}\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                validate_release_assets(
                    module_dir=module_dir,
                    repository="cbkii/ts-docsui",
                    tag="v1.2.3",
                    zip_path=zip_path,
                    checksum_path=checksum_path,
                )

    def test_embedded_module_metadata_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module_dir, zip_path, checksum_path = self.make_fixture(root)
            with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_STORED) as archive:
                archive.writestr(
                    "module.prop",
                    "id=ts18_documentsui_saf_full\nversion=v1.2.2\nversionCode=122\n",
                )
                for name in sorted(REQUIRED_ZIP_ENTRIES - {"module.prop"}):
                    archive.writestr(name, b"fixture")
            digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
            checksum_path.write_text(f"{digest}  {zip_path.name}\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                validate_release_assets(
                    module_dir=module_dir,
                    repository="cbkii/ts-docsui",
                    tag="v1.2.3",
                    zip_path=zip_path,
                    checksum_path=checksum_path,
                )

    def test_compressed_zip_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module_dir, zip_path, checksum_path = self.make_fixture(root)
            module_prop = (module_dir / "module.prop").read_text(encoding="utf-8")
            with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("module.prop", module_prop)
                for name in sorted(REQUIRED_ZIP_ENTRIES - {"module.prop"}):
                    archive.writestr(name, b"fixture")
            digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
            checksum_path.write_text(f"{digest}  {zip_path.name}\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                validate_release_assets(
                    module_dir=module_dir,
                    repository="cbkii/ts-docsui",
                    tag="v1.2.3",
                    zip_path=zip_path,
                    checksum_path=checksum_path,
                )


if __name__ == "__main__":
    unittest.main()
