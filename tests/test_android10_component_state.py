from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class Android10ComponentStateTests(unittest.TestCase):
    def test_service_uses_package_dump_when_getter_is_unavailable(self) -> None:
        source = (REPO_ROOT / "module/service.sh").read_text(encoding="utf-8")
        match = re.search(
            r"component_override_state\(\) \{(?P<body>.*?)\n\}",
            source,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match)
        body = match.group("body")
        self.assertIn("get-component-enabled-setting", body)
        self.assertIn('dumpsys package "$package"', body)
        self.assertIn("enabledComponents", body)
        self.assertIn("disabledComponents", body)
        self.assertIn("default", body)

    def test_runtime_component_reconciliation_remains_authoritative(self) -> None:
        source = (REPO_ROOT / "module/service.sh").read_text(encoding="utf-8")
        for component in (
            "com.android.documentsui/.picker.PickActivity",
            "com.android.documentsui/.files.FilesActivity",
            "com.android.documentsui/.files.LauncherActivity",
            "com.android.documentsui/.LauncherActivity",
            "com.android.documentsui/.ViewDownloadsActivity",
            "com.android.documentsui/.ScopedAccessActivity",
        ):
            with self.subTest(component=component):
                self.assertIn(component, source)


if __name__ == "__main__":
    unittest.main()
