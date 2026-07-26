from __future__ import annotations

import unittest
from pathlib import Path


class DocumentsUiPreferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        repo = Path(__file__).resolve().parents[1]
        cls.service = (repo / "module/service.sh").read_text(encoding="utf-8")

    def test_action_scoped_device_root_preferences_cover_picker_actions(self) -> None:
        # Android 10/Pie DocumentsUI uses includeDeviceRoot-<State.action>.
        # Cover the known action ranges used by the bundled and adjacent AOSP variants.
        for action in range(1, 9):
            with self.subTest(action=action):
                self.assertIn(f'name="includeDeviceRoot-{action}"', self.service)

    def test_default_shared_preferences_file_is_written(self) -> None:
        self.assertIn("com.android.documentsui_preferences.xml", self.service)

    def test_legacy_compatibility_keys_are_retained(self) -> None:
        for key in (
            'name="includeDeviceRoot"',
            'name="advancedDevices"',
            'name="showAdvanced"',
        ):
            with self.subTest(key=key):
                self.assertIn(key, self.service)


if __name__ == "__main__":
    unittest.main()
