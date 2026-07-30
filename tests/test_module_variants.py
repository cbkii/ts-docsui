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
main = MODULE.main


class ModuleVariantTests(unittest.TestCase):
    def make_module(self, root: Path) -> Path:
        module = root / "module"
        files = {
            "module.prop": "id=ts-docsui\nname=ts-docsui\nversion=v1.2.3\nversionCode=123\nauthor=cbkii\ndescription=test\n",
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

    def test_final_and_debug_names_and_inventory(self) -> None:
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
                self.assertFalse(DEBUG_ONLY & set(archive.namelist()))
            with zipfile.ZipFile(debug) as archive:
                self.assertTrue(DEBUG_ONLY <= set(archive.namelist()))


if __name__ == "__main__":
    unittest.main()
