from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (REPO_ROOT / ".github/workflows/release-magisk-module.yml").read_text(
    encoding="utf-8"
)
MODULE_PROP = (REPO_ROOT / "module/module.prop").read_text(encoding="utf-8")


class ReleaseWorkflowContractTests(unittest.TestCase):
    def test_repository_tests_run_before_release_metadata_mutation(self) -> None:
        tests = WORKFLOW.index("python3 -m unittest discover")
        prepare = WORKFLOW.index("- name: Prepare exact release metadata")
        self.assertLess(tests, prepare)

    def test_release_source_is_committed_after_artifact_validation(self) -> None:
        build_final = WORKFLOW.index("- name: Build lean final module")
        manifests = WORKFLOW.index("- name: Verify checksums and generate both update manifests")
        commit = WORKFLOW.index("- name: Commit exact new release source")
        verify_source = WORKFLOW.index("- name: Verify artifacts match committed release source")
        tag = WORKFLOW.index("- name: Create and push annotated tag")
        publish = WORKFLOW.index("- name: Publish new release or replace exact-tag assets")
        self.assertLess(build_final, manifests)
        self.assertLess(manifests, commit)
        self.assertLess(commit, verify_source)
        self.assertLess(verify_source, tag)
        self.assertLess(tag, publish)
        self.assertIn("module/module.prop", WORKFLOW)
        self.assertIn(
            "module/system/priv-app/TS18RootFileProvider/TS18RootFileProvider.apk",
            WORKFLOW,
        )
        self.assertIn("Unexpected tracked release changes", WORKFLOW)

    def test_release_publishes_both_magisk_update_manifests(self) -> None:
        self.assertIn("--variant final", WORKFLOW)
        self.assertIn("--variant debug", WORKFLOW)
        self.assertIn("--out dist/update.json", WORKFLOW)
        self.assertIn("--out dist/update-debug.json", WORKFLOW)
        self.assertIn(
            'assets=("${FINAL_ZIP}" "${FINAL_SHA}" "${DEBUG_ZIP}" "${DEBUG_SHA}" dist/update.json dist/update-debug.json)',
            WORKFLOW,
        )

    def test_source_module_uses_public_stable_update_url(self) -> None:
        self.assertIn(
            "updateJson=https://github.com/cbkii/ts-docsui/releases/latest/download/update.json",
            MODULE_PROP,
        )


if __name__ == "__main__":
    unittest.main()
