from __future__ import annotations

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
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
                if depth == 0:
                    return source[brace + 1 : index]
        self.fail(f"unterminated method: {signature}")

    def test_module_identity_is_simple_and_old_id_is_absent(self) -> None:
        self.assertIn("id=ts-docsui", self.read("module/module.prop"))
        all_text = "\n".join(
            path.read_text(encoding="utf-8", errors="ignore")
            for path in REPO_ROOT.rglob("*")
            if path.is_file() and ".git" not in path.parts
        )
        self.assertNotIn("ts18_documentsui_saf_full", all_text)

    def test_runtime_output_is_download_only_and_state_is_small(self) -> None:
        service = self.read("module/service.sh")
        self.assertIn("STATE=/data/adb/ts-docsui", service)
        self.assertIn("OUT=/storage/emulated/0/Download/ts-docsui", service)
        self.assertIn("LOG=/dev/null", service)
        self.assertNotIn("/data/adb/ts-docsui/logs", service)
        self.assertNotIn("/data/adb/ts-docsui/diagnostics", service)

    def test_runtime_config_loader_accepts_known_safe_values(self) -> None:
        service = self.read("module/service.sh")
        body = self.method_body(service, "load_cfg()")
        self.assertIn('case "$key" in', body)
        self.assertIn('case "$value" in', body)
        self.assertIn('set_cfg "$key" "$value"', body)
        self.assertNotIn('case "$key:$value"', body)

    def test_component_state_has_android10_package_dump_fallback(self) -> None:
        service = self.read("module/service.sh")
        body = self.method_body(service, "component_state()")
        self.assertIn("get-component-enabled-setting", body)
        self.assertIn('dumpsys package "$package"', body)
        self.assertIn("enabledComponents", body)
        self.assertIn("disabledComponents", body)

    def test_root_provider_failure_is_isolated_from_stock_provider(self) -> None:
        service = self.read("module/service.sh")
        start = service.index('if on "$FIX_ENABLE_ROOT_FILE_PROVIDER"')
        end = service.index('if on "$FIX_GRANT_STORAGE_ACCESS"', start)
        block = service[start:end]
        self.assertNotIn("com.android.externalstorage", block)
        self.assertIn('set_component disabled "$ROOT_COMPONENT"', block)
        self.assertIn("stock storage remains enabled", block)

    def test_boot_warmup_does_not_start_custom_provider(self) -> None:
        service = self.read("module/service.sh")
        start = service.index('if on "$FIX_WARM_UP_PROVIDERS"')
        end = service.index('on "$FIX_VERIFY_PICKER_RESOLVER"', start)
        block = service[start:end]
        self.assertIn("downloads.documents/root", block)
        self.assertIn("externalstorage.documents/root", block)
        self.assertNotIn("cbkii.tsdocsui.root.documents", block)

    def test_diagnostics_work_only_in_download(self) -> None:
        diagnostic = self.read("module/tools/ts18-saf-deepdiag.sh")
        self.assertIn("/storage/emulated/0/Download/ts-docsui/diagnostics", diagnostic)
        self.assertNotIn("/data/adb/ts-docsui/diagnostics", diagnostic)
        self.assertIn("timeout", diagnostic)
        self.assertIn("tar -tzf", diagnostic)

    def test_root_provider_uses_current_helper_and_stage_paths(self) -> None:
        shell = self.read(
            "rootprovider/src/main/java/com/cbkii/tsdocsui/rootprovider/RootShell.java"
        )
        provider = self.read(
            "rootprovider/src/main/java/com/cbkii/tsdocsui/rootprovider/RootDocumentsProvider.java"
        )
        self.assertIn('/data/adb/ts-docsui/rootfs-helper.sh', shell)
        self.assertIn('/storage/emulated/0/.ts-docsui-root-provider', provider)
        self.assertNotIn('/data/adb/ts18-documentsui-saf', shell + provider)
        self.assertNotIn('/storage/emulated/0/.TS18-Root-Provider', shell + provider)

    def test_legacy_wrappers_collectors_and_version_sync_are_removed(self) -> None:
        obsolete = (
            ".github/workflows/apply-android10-service-fix.yml",
            "module/tools/ts18-saf-diagnose.sh",
            "module/tools/ts18-saf-launch.sh",
            "module/tools/ts18-saf-evidence-v2.sh",
            "module/tools/ts18-saf-evidence-common.sh",
            "module/tools/ts18-saf-evidence-remount.sh",
            "scripts/sync_runtime_version.py",
            "tests/test_sync_runtime_version.py",
        )
        for relative in obsolete:
            with self.subTest(relative=relative):
                self.assertFalse((REPO_ROOT / relative).exists())

    def test_installer_is_latest_only_and_supports_optional_debug_payload(self) -> None:
        installer = self.read("module/customize.sh")
        self.assertIn("MODID=ts-docsui", installer)
        self.assertIn("zip_has action.sh", installer)
        self.assertNotIn("OLD_MODID", installer)
        self.assertNotIn("old_schema", installer)
        self.assertNotIn("ts18_documentsui_saf_full", installer)

    def test_final_and_debug_zip_contract_is_encoded(self) -> None:
        builder = self.read("scripts/build-magisk-zip.py")
        self.assertIn('choices=("final", "debug")', builder)
        self.assertIn('"ts-docsui-debug"', builder)
        self.assertIn('"ts-docsui"', builder)
        self.assertIn("DEBUG_ONLY", builder)


if __name__ == "__main__":
    unittest.main()
