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
            "\n}\n\nrefresh_picker_once()", 1
        )[0]

    def test_preference_write_loop_targets_default_preferences_file(self) -> None:
        match = re.search(r"for name in ([^;]+); do", self.function)
        self.assertIsNotNone(match, "DocumentsUI preference filename loop is missing")
        filenames = shlex.split(match.group(1))
        self.assertIn("com.android.documentsui_preferences.xml", filenames)
        self.assertIn('cat > "$file" <<EOPREF', self.function)

    def test_action_scoped_preferences_form_well_formed_runtime_xml(self) -> None:
        match = re.search(
            r'cat > "\$file" <<EOPREF\n(?P<xml>.*?)\nEOPREF',
            self.function,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match, "DocumentsUI preference XML heredoc is missing")

        runtime_xml = match.group("xml").replace("$value", "true")
        root = ElementTree.fromstring(runtime_xml)
        entries = {element.attrib.get("name"): element for element in root}

        expected = {
            "includeDeviceRoot",
            *(f"includeDeviceRoot-{action}" for action in range(1, 9)),
            "showAdvanced",
            "advancedDevices",
            "showDeviceStorageOption",
            "fileSize",
        }
        self.assertTrue(expected.issubset(entries), expected - entries.keys())
        for name in expected:
            with self.subTest(name=name):
                self.assertEqual(entries[name].tag, "boolean")
                self.assertEqual(entries[name].attrib.get("value"), "true")


if __name__ == "__main__":
    unittest.main()
