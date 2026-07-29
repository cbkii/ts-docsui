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

    def test_non_truncating_stage_initialisation_fails_closed(self) -> None:
        source = self.read(
            "rootprovider/src/main/java/com/cbkii/tsdocsui/rootprovider/RootDocumentsProvider.java"
        )
        body = self.method_body(source, "private ParcelFileDescriptor openStaged(")
        self.assertIn("!copyOutLocally(sourcePath, stage)", body)
        self.assertIn("RootShell.copyOut(sourcePath, stage", body)
        self.assertNotIn("RootShell.stat(sourcePath)", body)
        self.assertLess(
            body.index("!copyOutLocally(sourcePath, stage)"),
            body.index("RootShell.copyOut(sourcePath, stage"),
        )
        self.assertIn('throw fileNotFound("Open failed", e)', body)

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

    def test_service_logs_best_effort_repairs_and_hardens_rm(self) -> None:
        service = self.read("module/service.sh")
        load_config = self.method_body(service, "load_config()")
        enable_pkg = self.method_body(service, "enable_pkg()")
        refresh = self.method_body(service, "refresh_picker_once()")
        self.assertNotIn('chmod 0644 "$CFG" 2>/dev/null || true', load_config)
        self.assertIn("runtime config created but chmod 0644 was rejected", load_config)
        self.assertIn('record_noop "package already enabled', enable_pkg)
        self.assertIn('if ! pkg_installed_for_user "$package"', enable_pkg)
        self.assertIn("pm install-existing --user", enable_pkg)
        self.assertIn('rm -f -- "$base"/databases/roots.db*', refresh)

    def test_boot_reconciler_has_explicit_noop_boundaries(self) -> None:
        service = self.read("module/service.sh")
        required = (
            "record_mutation()",
            "record_noop()",
            "pkg_enabled_for_user()",
            "component_override_state()",
            "permission_granted()",
            "appop_allowed()",
            "install_if_changed()",
            "run_migration_once()",
            'record_noop "package already enabled',
            'record_noop "component already enabled',
            'record_noop "permission already granted',
            'record_noop "app-op already allowed',
            'cmp -s "$generated" "$target"',
            'record_noop "root helper already current',
            'record_noop "Magisk root policy already granted',
            'record_noop "root provider staging mode already current',
            'reconcile summary mutations=$MUTATION_COUNT noops=$NOOP_COUNT',
        )
        for marker in required:
            with self.subTest(marker=marker):
                self.assertIn(marker, service)

    def test_destructive_repairs_are_one_time_or_mismatch_gated(self) -> None:
        service = self.read("module/service.sh")
        owner = self.method_body(service, "repair_package_data_owner()")
        self.assertLess(owner.index("mismatch=$(find"), owner.index('chown -R "$uid:$uid"'))
        self.assertIn("run_migration_once stale-provider-v121", service)
        self.assertIn("run_migration_once picker-preferred-v121", service)
        self.assertEqual(
            1,
            service.count("repair_package_data_owner com.android.documentsui"),
            "DocumentsUI ownership must not receive a duplicate recursive pass",
        )

    def test_root_provider_failure_does_not_mutate_stock_external_provider(self) -> None:
        service = self.read("module/service.sh")
        start = service.index('if is_on "$FIX_ENABLE_ROOT_FILE_PROVIDER"')
        end = service.index("MIXPLORER_PKG=", start)
        root_block = service[start:end]
        self.assertNotIn("com.android.externalstorage", root_block)
        self.assertIn('disable_component "$ROOT_COMPONENT"', root_block)

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
