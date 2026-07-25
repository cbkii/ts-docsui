from __future__ import annotations

import unittest
from pathlib import Path

from scripts.sync_runtime_version import synced_text


class SyncRuntimeVersionTests(unittest.TestCase):
    def test_service_markers_are_synchronized(self) -> None:
        source = '''LOG=$LOGDIR/service-v100.log\n  desired="v1.0.0:$show:$config_hash"\nlog "===== TS18 Full File Picker v1.0.0 start ====="\n'''
        updated = synced_text(Path('module/service.sh'), source, 'v1.2.3', '123')
        self.assertIn('service-v123.log', updated)
        self.assertIn('desired="v1.2.3:$show:$config_hash"', updated)
        self.assertIn('TS18 Full File Picker v1.2.3 start', updated)

    def test_diagnostic_marker_is_synchronized(self) -> None:
        source = 'RUN_ID=ts18-docsui-v100-${MODE}-${TS}\n'
        updated = synced_text(
            Path('module/tools/ts18-saf-deepdiag.sh'), source, 'v1.2.3', '123'
        )
        self.assertEqual(updated, 'RUN_ID=ts18-docsui-v123-${MODE}-${TS}\n')


if __name__ == '__main__':
    unittest.main()
