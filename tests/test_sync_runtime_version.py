from __future__ import annotations

import unittest
from pathlib import Path

from scripts.sync_runtime_version import synced_text


class SyncRuntimeVersionTests(unittest.TestCase):
    def test_service_markers_are_synchronized(self) -> None:
        source = '''LOG=$LOGDIR/service-v100.log
  desired="v1.0.0:$show:$config_hash"
log "===== TS18 Full File Picker v1.0.0 start ====="
'''
        updated = synced_text(Path('module/service.sh'), source, 'v1.2.3', '123')
        self.assertIn('service-v123.log', updated)
        self.assertIn('desired="v1.2.3:$show:$config_hash"', updated)
        self.assertIn('TS18 Full File Picker v1.2.3 start', updated)

    def test_non_generated_runtime_files_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, 'Unsupported runtime file'):
            synced_text(
                Path('module/tools/ts18-saf-evidence-v2.sh'),
                'VERSION=dynamic\n',
                'v1.2.3',
                '123',
            )


if __name__ == '__main__':
    unittest.main()
