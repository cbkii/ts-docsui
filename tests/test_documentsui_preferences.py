from __future__ import annotations

import re
import shlex
import unittest
import xml.etree.ElementTree as ElementTree
from pathlib import Path


class DocumentsUiPreferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        repo = Path(__file__).resolve().parents[1]
        cls.service = (repo / "module/service.sh").read_text(encoding="utf-8")
        cls.function = cls.service.split("write_documentsui_prefs() {", 1)[1].split(
            "\n}\n\ninstall_helper()", 1
        )[0]

    def test_preference_write_loop_targets_all_supported_files(self) -> None:
        match = re.search(r"for name in ([^;]+); do", self.function)
        self.assertIsNotNone(match, "DocumentsUI preference filename loop is missing")
        filenames = shlex.split(match.group(1))
        self.assertEqual(
            filenames,
            [
                "com.android.documentsui_preferences.xml",
                "com.android.documentsui.xml",
                "DocumentsUI.xml",
            ],
        )
        self.assertIn('template=$GEN/documentsui.xml', self.function)
        self.assertIn('cp -f "$template" "$GEN/$name"', self.function)
        self.assertIn(
            'install_changed "$GEN/$name" "$base/$name" "$uid" 600',
            self.function,
        )

    def test_generated_action_scoped_preferences_are_well_formed(self) -> None:
        match = re.search(
            r"for key in (?P<keys>[^;]+); do echo \"<boolean name=\\\"\$key\\\" value=\\\"\$value\\\" />\"; done",
            self.function,
        )
        self.assertIsNotNone(match, "DocumentsUI preference key loop is missing")
        keys = shlex.split(match.group("keys"))
        expected = {
            "includeDeviceRoot",
            *(f"includeDeviceRoot-{action}" for action in range(1, 9)),
            "showAdvanced",
            "advancedDevices",
            "showDeviceStorageOption",
        }
        self.assertEqual(set(keys), expected)
        self.assertIn("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>", self.function)
        self.assertIn("} >\"$template\"", self.function)
        self.assertIn('<boolean name="fileSize" value="true" />', self.function)

        runtime_xml = "<map>" + "".join(
            f'<boolean name="{key}" value="true" />' for key in keys
        ) + '<boolean name="fileSize" value="true" /></map>'
        root = ElementTree.fromstring(runtime_xml)
        entries = {element.attrib.get("name"): element for element in root}
        self.assertTrue((expected | {"fileSize"}).issubset(entries))
        for name in expected | {"fileSize"}:
            with self.subTest(name=name):
                self.assertEqual(entries[name].tag, "boolean")
                self.assertEqual(entries[name].attrib.get("value"), "true")


if __name__ == "__main__":
    unittest.main()
