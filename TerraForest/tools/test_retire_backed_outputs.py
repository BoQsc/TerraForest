# SPDX-License-Identifier: 0BSD
import json
from pathlib import Path
import tempfile
import unittest
import os
import stat
from unittest.mock import patch
from generated_backup import catalog
from retained_artifacts import digest
from retire_backed_outputs import candidates,retire_outputs


class ColdOutputTests(unittest.TestCase):
    def test_latest_captures_references_pins_and_archives_are_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            for i in range(4):
                folder=root/'reports/checks'/str(i);folder.mkdir(parents=True)
                (folder/'image.png').write_bytes(b'picture')
                (folder/'run.json').write_text('{}')
            for name in ('retained_artifacts/chunks/data.png','legacy/referenced.png','pinned/image.png'):
                path=root/'reports'/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'evidence')
            (root/'reports/pinned/RETAIN_READY').touch()
            record=catalog(dict(roots={'project/reports':str(root/'reports')}),root/'catalog.json')
            selected,_=candidates(record,root,{'project/reports/legacy/referenced.png'})
            self.assertEqual({r['path'] for r in selected},{'project/reports/checks/0/image.png','project/reports/checks/1/image.png'})

    def test_changed_output_prevents_entire_retirement_batch(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);folder=root/'reports/old';folder.mkdir(parents=True)
            for name in ('a.png','b.png'):(folder/name).write_bytes(name.encode())
            manifest=root/'catalog.json';record=catalog(dict(roots={'project/reports':str(root/'reports')}),manifest)
            receipt=root/'upload.json';receipt.write_text(json.dumps(dict(complete=True,catalog_sha256=digest(manifest),
                repository='BoQsc/TerraForest',branch='codex/generated-backup-2026-11-10',tag='backup/test',
                assets=[dict(id=1,objects=[r['sha256'] for r in record['files']])])) )
            (folder/'b.png').write_bytes(b'new evidence')
            with patch('retire_backed_outputs.GitHub'),patch('retire_backed_outputs.no_game_processes'),patch('retire_backed_outputs.referenced_media',return_value=set()):
                with self.assertRaisesRegex(ValueError,'Changed output retained'):
                    retire_outputs(manifest,receipt,root,apply=True)
            self.assertEqual((folder/'a.png').read_bytes(),b'a.png')
            self.assertEqual((folder/'b.png').read_bytes(),b'new evidence')

    def test_verified_retirement_preserves_metadata_and_writes_restore_pointer(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);folder=root/'reports/old';folder.mkdir(parents=True)
            (folder/'image.png').write_bytes(b'image')
            if os.name == 'nt':(folder/'image.png').chmod(stat.S_IREAD)
            (folder/'run.json').write_text('{}')
            manifest=root/'catalog.json';record=catalog(dict(roots={'project/reports':str(root/'reports')}),manifest)
            receipt=root/'upload.json';receipt.write_text(json.dumps(dict(complete=True,catalog_sha256=digest(manifest),
                repository='BoQsc/TerraForest',branch='codex/generated-backup-2026-11-10',tag='backup/test',
                assets=[dict(id=1,objects=[r['sha256'] for r in record['files']])])) )
            with patch('retire_backed_outputs.GitHub'),patch('retire_backed_outputs.no_game_processes'),patch('retire_backed_outputs.referenced_media',return_value=set()):
                result=retire_outputs(manifest,receipt,root,apply=True)
            self.assertEqual(len(result['removed']),1)
            self.assertFalse((folder/'image.png').exists())
            self.assertTrue((folder/'run.json').exists())
            pointer=json.loads((folder/'.cold-archive-20261110.json').read_text())
            self.assertIn('image.png',pointer['files'])


if __name__=='__main__':unittest.main()
