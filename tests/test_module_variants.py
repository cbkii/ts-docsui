from __future__ import annotations

import importlib.util
import tempfile
import unittest
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build_magisk_zip", REPO_ROOT / "scripts/build-magisk-zip.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
DEBUG_ONLY = MODULE.DEBUG_ONLY
DEBUG_REQUIRED = MODULE.DEBUG_REQUIRED
FINAL_EXCLUDE = MODULE.FINAL_EXCLUDE
UPDATE_JSON_URLS = MODULE.UPDATE_JSON_URLS
main = MODULE.main


class ModuleVariantTests(unittest.TestCase):
    def make_module(self, root: Path) -> Path:
        module = root / "module"
        files = {
            "module.prop": (
                "id=ts-docsui\n"
                "name=ts-docsui\n"
                "version=v1.2.3\n"
                "versionCode=123\n"
                "author=cbkii\n"
                "description=test\n"
                f"updateJson={UPDATE_JSON_URLS['final']}\n"
            ),
            "customize.sh": "#!/system/bin/sh\n",
            "service.sh": "#!/system/bin/sh\n",
            "post-fs-data.sh": "#!/system/bin/sh\n",
            "uninstall.sh": "#!/system/bin/sh\n",
            "action.sh": "#!/system/bin/sh\n",
            "README.md": "test\n",
            "tools/rootfs-helper.sh": "#!/system/bin/sh\n",
            "tools/ts18-saf-deepdiag.sh": "#!/system/bin/sh\n",
        }
        for relative, content in files.items():
            path = module / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        return module

    @staticmethod
    def read_props(archive: zipfile.ZipFile) -> dict[str, str]:
        props: dict[str, str] = {}
        for line in archive.read("module.prop").decode("utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                props[key] = value
        return props

    def test_final_and_debug_names_inventory_and_update_channels(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module = self.make_module(root)
            out = root / "dist"
            self.assertEqual(main(["--module-dir", str(module), "--out-dir", str(out), "--variant", "final"]), 0)
            self.assertEqual(main(["--module-dir", str(module), "--out-dir", str(out), "--variant", "debug"]), 0)
            final = out / "ts-docsui-v123.zip"
            debug = out / "ts-docsui-debug-v123.zip"
            self.assertTrue(final.is_file())
            self.assertTrue(debug.is_file())
            with zipfile.ZipFile(final) as archive:
                final_names = set(archive.namelist())
                self.assertFalse(FINAL_EXCLUDE & final_names)
                self.assertEqual(self.read_props(archive)["updateJson"], UPDATE_JSON_URLS["final"])
            with zipfile.ZipFile(debug) as archive:
                debug_names = set(archive.namelist())
                self.assertTrue(DEBUG_REQUIRED <= debug_names)
                self.assertTrue(DEBUG_ONLY <= debug_names)
                self.assertEqual(self.read_props(archive)["updateJson"], UPDATE_JSON_URLS["debug"])

    def test_missing_source_update_channel_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module = self.make_module(root)
            module_prop = module / "module.prop"
            module_prop.write_text(
                module_prop.read_text(encoding="utf-8").replace(
                    f"updateJson={UPDATE_JSON_URLS['final']}\n", ""
                ),
                encoding="utf-8",
            )
            self.assertEqual(
                main(["--module-dir", str(module), "--out-dir", str(root / "dist"), "--variant", "final"]),
                1,
            )


if __name__ == "__main__":
    unittest.main()
