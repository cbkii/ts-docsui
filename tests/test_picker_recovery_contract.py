from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class PickerRecoveryContractTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (REPO_ROOT / relative).read_text(encoding="utf-8")

    def method_body(self, source: str, signature: str) -> str:
        start = source.index(signature)
        brace = source.index("{", start)
        depth = 0
        for index in range(brace, len(source)):
            char = source[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    return source[brace + 1 : index]
        self.fail(f"unterminated method: {signature}")

    def test_query_roots_never_invokes_magisk_or_root_shell(self) -> None:
        source = self.read(
            "rootprovider/src/main/java/com/cbkii/tsdocsui/rootprovider/RootDocumentsProvider.java"
        )
        body = self.method_body(source, "public Cursor queryRoots(String[] projection)")
        self.assertNotIn("RootShell", body)
        self.assertNotIn("su", body.lower())
        self.assertIn("addFastRoot", body)

    def test_root_document_metadata_has_non_root_fast_path(self) -> None:
        source = self.read(
            "rootprovider/src/main/java/com/cbkii/tsdocsui/rootprovider/RootDocumentsProvider.java"
        )
        body = self.method_body(source, "private RootEntry entryFor(ParsedId parsed)")
        self.assertIn("localEntry", body)
        self.assertIn("syntheticRootEntry", body)
        self.assertLess(body.index("localEntry"), body.index("RootShell.stat"))

    def test_non_device_storage_lists_locally_before_root_fallback(self) -> None:
        source = self.read(
            "rootprovider/src/main/java/com/cbkii/tsdocsui/rootprovider/RootDocumentsProvider.java"
        )
        body = self.method_body(source, "private List<RootEntry> listEntries(ParsedId parent)")
        self.assertIn("!ROOT_DEVICE.equals", body)
        self.assertIn("localChildren", body)
        self.assertLess(body.index("localChildren"), body.index("RootShell.list"))

    def test_root_metadata_and_listing_are_bounded(self) -> None:
        source = self.read(
            "rootprovider/src/main/java/com/cbkii/tsdocsui/rootprovider/RootShell.java"
        )
        self.assertIn('run(4, "stat", path)', source)
        self.assertIn('run(LIST_TIMEOUT_SECONDS, "list", path)', source)
        self.assertRegex(source, r"LIST_TIMEOUT_SECONDS\s*=\s*8L")

    def test_service_repairs_known_v101_launch_breakages(self) -> None:
        service = self.read("module/service.sh")
        required = (
            "repair_package_data_owner com.android.documentsui",
            "cleanup_stale_provider",
            "com.ts18.safprovider",
            "clear_picker_preferred_activities",
            "verify_picker_resolver",
            "com.android.documentsui/.picker.PickActivity",
            "com.android.documentsui/.files.LauncherActivity",
            "com.android.documentsui/.ViewDownloadsActivity",
            "com.android.documentsui/.ScopedAccessActivity",
        )
        for marker in required:
            with self.subTest(marker=marker):
                self.assertIn(marker, service)

    def test_service_does_not_report_unconditional_component_success(self) -> None:
        service = self.read("module/service.sh")
        body = self.method_body(service, "enable_component()")
        self.assertIn("rc=$?", body)
        self.assertIn('if [ "$rc" -eq 0 ]', body)
        self.assertIn("ERROR: failed to enable component", body)

    def test_default_config_forces_proven_primary_root_visible(self) -> None:
        config = self.read("module/config.default")
        self.assertRegex(config, r"(?m)^CONFIG_SCHEMA=2$")
        self.assertRegex(config, r"(?m)^EXTERNAL_ROOT_MODE=show$")
        self.assertRegex(config, r"(?m)^FIX_REPAIR_DOCUMENTSUI_DATA_OWNER=1$")
        self.assertRegex(config, r"(?m)^FIX_DISABLE_STALE_TS18_PROVIDER=1$")
        self.assertRegex(config, r"(?m)^FIX_VERIFY_PICKER_RESOLVER=1$")

    def test_installer_migrates_old_auto_mode_only_once(self) -> None:
        installer = self.read("module/customize.sh")
        self.assertIn("old_schema", installer)
        self.assertIn('if [ "$old_schema" -lt 2 ]', installer)
        self.assertIn("EXTERNAL_ROOT_MODE=show", installer)
        self.assertNotIn("EXTERNAL_ROOT_MODE=auto/' \"$merged\"", installer)

    def test_sysconfig_declares_all_picker_entrypoints(self) -> None:
        sysconfig = self.read("module/system/etc/sysconfig/ts18-documentsui-saf.xml")
        expected = (
            "com.android.documentsui.picker.PickActivity",
            "com.android.documentsui.files.FilesActivity",
            "com.android.documentsui.files.LauncherActivity",
            "com.android.documentsui.LauncherActivity",
            "com.android.documentsui.ViewDownloadsActivity",
            "com.android.documentsui.ScopedAccessActivity",
        )
        for component in expected:
            with self.subTest(component=component):
                self.assertIn(component, sysconfig)

    def test_manual_launcher_uses_explicit_documentsui_component(self) -> None:
        launcher = self.read("module/tools/ts18-saf-launch.sh")
        self.assertIn("PICKER=com.android.documentsui/.picker.PickActivity", launcher)
        self.assertIn('am start -n "$PICKER"', launcher)

    def test_shell_quote_emits_posix_embedded_quote_sequence(self) -> None:
        source = self.read(
            "rootprovider/src/main/java/com/cbkii/tsdocsui/rootprovider/RootShell.java"
        )
        line = next(line for line in source.splitlines() if "value.replace" in line)
        self.assertIn(r'''value.replace("'", "'\\''")''', line)

    def test_missing_timeout_never_hides_primary_storage(self) -> None:
        service = self.read("module/service.sh")
        self.assertIn("BOUNDED_COMMAND_SKIPPED=125", service)
        self.assertIn("kept primary visible", service)
        self.assertIn("/system/bin/toybox timeout", service)


if __name__ == "__main__":
    unittest.main()
