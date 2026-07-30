from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from scripts.release_version import apply_release, parse_semver, resolve_release


class ReleaseVersionTests(unittest.TestCase):
    def test_blank_input_bumps_current_patch_and_code(self) -> None:
        result = resolve_release(
            current_version="v1.0.0",
            current_version_code="100",
            tags=[],
        )
        self.assertEqual(result["release_tag"], "v1.0.1")
        self.assertEqual(result["release_version_code"], "101")
        self.assertEqual(result["version_source"], "auto-patch")

    def test_blank_input_resumes_current_untagged_release(self) -> None:
        result = resolve_release(
            current_version="v1.3.1",
            current_version_code="131",
            tags=["v1.3.0"],
        )
        self.assertEqual(result["release_tag"], "v1.3.1")
        self.assertEqual(result["release_version_code"], "131")
        self.assertEqual(result["version_source"], "resume-current-untagged")
        self.assertEqual(result["version_code_source"], "current-version")
        self.assertFalse(result["metadata_change"])

    def test_latest_tag_wins_as_auto_bump_base(self) -> None:
        result = resolve_release(
            current_version="v1.0.0",
            current_version_code="100",
            tags=["v1.3.9", "v1.4.2", "not-a-version"],
        )
        self.assertEqual(result["release_tag"], "v1.4.3")
        self.assertEqual(result["previous_tag"], "v1.4.2")

    def test_explicit_version_accepts_optional_v(self) -> None:
        result = resolve_release(
            current_version="v1.0.0",
            current_version_code="100",
            tags=["v1.0.0"],
            requested_version="1.2.0",
        )
        self.assertEqual(result["release_tag"], "v1.2.0")

    def test_explicit_version_code_is_used(self) -> None:
        result = resolve_release(
            current_version="v1.0.0",
            current_version_code="100",
            tags=[],
            requested_version="v1.0.1",
            requested_version_code="150",
        )
        self.assertEqual(result["release_version_code"], "150")
        self.assertTrue(result["version_code_increases"])

    def test_new_version_rejects_non_increasing_version_code(self) -> None:
        with self.assertRaises(ValueError):
            resolve_release(
                current_version="v1.0.0",
                current_version_code="100",
                tags=[],
                requested_version="v1.0.1",
                requested_version_code="100",
            )

    def test_current_version_rejects_lower_version_code(self) -> None:
        with self.assertRaises(ValueError):
            resolve_release(
                current_version="v1.0.1",
                current_version_code="101",
                tags=["v1.0.0"],
                requested_version="v1.0.1",
                requested_version_code="100",
            )

    def test_explicit_current_version_reuses_current_code_for_resume(self) -> None:
        result = resolve_release(
            current_version="v1.0.1",
            current_version_code="101",
            tags=["v1.0.0"],
            requested_version="v1.0.1",
        )
        self.assertEqual(result["release_tag"], "v1.0.1")
        self.assertEqual(result["release_version_code"], "101")
        self.assertEqual(result["version_code_source"], "current-version")
        self.assertFalse(result["metadata_change"])

    def test_lower_version_than_module_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            resolve_release(
                current_version="v2.0.0",
                current_version_code="200",
                tags=[],
                requested_version="v1.9.9",
            )

    def test_lower_version_than_latest_tag_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            resolve_release(
                current_version="v1.0.0",
                current_version_code="100",
                tags=["v1.2.0"],
                requested_version="v1.1.0",
            )

    def test_lower_version_can_be_resolved_for_exact_release_rebuild(self) -> None:
        result = resolve_release(
            current_version="v2.0.0",
            current_version_code="200",
            tags=["v1.9.9"],
            requested_version="v1.9.9",
            allow_lower_version=True,
        )
        self.assertEqual(result["release_tag"], "v1.9.9")
        self.assertFalse(result["version_increases"])

    def test_invalid_version_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            parse_semver("v1.2")

    def test_apply_updates_only_release_properties(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "module.prop"
            path.write_text(
                "id=ts-docsui\nversion=v1.0.0\nversionCode=100\nauthor=cbkii\n",
                encoding="utf-8",
            )
            apply_release(path, "v1.0.1", "101")
            self.assertEqual(
                path.read_text(encoding="utf-8"),
                "id=ts-docsui\nversion=v1.0.1\nversionCode=101\nauthor=cbkii\n",
            )


if __name__ == "__main__":
    unittest.main()
