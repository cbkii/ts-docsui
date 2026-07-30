from __future__ import annotations

import hashlib
import tempfile
import unittest
import zipfile
from pathlib import Path

from scripts.release_assets import (
    DEBUG_ONLY_ENTRIES,
    DEBUG_REQUIRED_ENTRIES,
    REQUIRED_ZIP_ENTRIES,
    UPDATE_JSON_URLS,
    validate_release_assets,
)


class ReleaseAssetTests(unittest.TestCase):
    def make_fixture(self, root: Path, *, variant: str = "final") -> tuple[Path, Path, Path]:
        module_dir = root / "module"
        module_dir.mkdir()
        source_prop = (
            "id=ts-docsui\n"
            "name=ts-docsui\n"
            "version=v1.2.3\n"
            "versionCode=123\n"
            f"updateJson={UPDATE_JSON_URLS['final']}\n"
        )
        (module_dir / "module.prop").write_text(source_prop, encoding="utf-8")
        prefix = "ts-docsui-debug" if variant == "debug" else "ts-docsui"
        zip_path = root / f"{prefix}-v123.zip"
        embedded_prop = source_prop.replace(
            f"updateJson={UPDATE_JSON_URLS['final']}",
            f"updateJson={UPDATE_JSON_URLS[variant]}",
        )
        entries = set(REQUIRED_ZIP_ENTRIES)
        if variant == "debug":
            entries |= DEBUG_REQUIRED_ENTRIES
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("module.prop", embedded_prop)
            for name in sorted(entries - {"module.prop"}):
                archive.writestr(name, b"fixture")
        digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
        checksum_path = zip_path.with_suffix(".zip.sha256")
        checksum_path.write_text(f"{digest}  {zip_path.name}\n", encoding="utf-8")
        return module_dir, zip_path, checksum_path

    def validate(
        self,
        module_dir: Path,
        zip_path: Path,
        checksum_path: Path,
        *,
        variant: str = "final",
    ):
        return validate_release_assets(
            module_dir=module_dir,
            repository="cbkii/ts-docsui",
            tag="v1.2.3",
            zip_path=zip_path,
            checksum_path=checksum_path,
            variant=variant,
        )

    def test_exact_final_release_assets_validate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            module_dir, zip_path, checksum_path = self.make_fixture(Path(directory))
            payload, digest = self.validate(module_dir, zip_path, checksum_path)
            self.assertEqual(payload["version"], "v1.2.3")
            self.assertEqual(payload["versionCode"], 123)
            self.assertTrue(payload["zipUrl"].endswith("/ts-docsui-v123.zip"))
            self.assertEqual(len(digest), 64)

    def test_exact_debug_release_assets_validate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            module_dir, zip_path, checksum_path = self.make_fixture(
                Path(directory), variant="debug"
            )
            payload, _ = self.validate(
                module_dir, zip_path, checksum_path, variant="debug"
            )
            self.assertTrue(payload["zipUrl"].endswith("/ts-docsui-debug-v123.zip"))

    def test_checksum_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            module_dir, zip_path, checksum_path = self.make_fixture(Path(directory))
            checksum_path.write_text(f"{'0' * 64}  {zip_path.name}\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                self.validate(module_dir, zip_path, checksum_path)

    def test_debug_payload_is_rejected_from_final_release(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module_dir, zip_path, checksum_path = self.make_fixture(root)
            module_prop = (module_dir / "module.prop").read_text(encoding="utf-8")
            with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_STORED) as archive:
                archive.writestr("module.prop", module_prop)
                for name in sorted((REQUIRED_ZIP_ENTRIES | DEBUG_ONLY_ENTRIES) - {"module.prop"}):
                    archive.writestr(name, b"fixture")
            digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
            checksum_path.write_text(f"{digest}  {zip_path.name}\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "debug-only"):
                self.validate(module_dir, zip_path, checksum_path)

    def test_wrong_embedded_update_channel_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module_dir, zip_path, checksum_path = self.make_fixture(root)
            with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_STORED) as archive:
                archive.writestr(
                    "module.prop",
                    (module_dir / "module.prop")
                    .read_text(encoding="utf-8")
                    .replace(UPDATE_JSON_URLS["final"], UPDATE_JSON_URLS["debug"]),
                )
                for name in sorted(REQUIRED_ZIP_ENTRIES - {"module.prop"}):
                    archive.writestr(name, b"fixture")
            digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
            checksum_path.write_text(f"{digest}  {zip_path.name}\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "updateJson"):
                self.validate(module_dir, zip_path, checksum_path)

    def test_embedded_metadata_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module_dir, zip_path, checksum_path = self.make_fixture(root)
            with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_STORED) as archive:
                archive.writestr(
                    "module.prop",
                    "id=ts-docsui\nversion=v1.2.2\nversionCode=122\n"
                    f"updateJson={UPDATE_JSON_URLS['final']}\n",
                )
                for name in sorted(REQUIRED_ZIP_ENTRIES - {"module.prop"}):
                    archive.writestr(name, b"fixture")
            digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
            checksum_path.write_text(f"{digest}  {zip_path.name}\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                self.validate(module_dir, zip_path, checksum_path)

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
                self.validate(module_dir, zip_path, checksum_path)

    def test_zip64_local_header_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module_dir, zip_path, checksum_path = self.make_fixture(root)
            module_prop = (module_dir / "module.prop").read_bytes()
            with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_STORED, allowZip64=True) as archive:
                with archive.open("module.prop", "w", force_zip64=True) as handle:
                    handle.write(module_prop)
                for name in sorted(REQUIRED_ZIP_ENTRIES - {"module.prop"}):
                    archive.writestr(name, b"fixture")
            digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
            checksum_path.write_text(f"{digest}  {zip_path.name}\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "ZIP64"):
                self.validate(module_dir, zip_path, checksum_path)


if __name__ == "__main__":
    unittest.main()
