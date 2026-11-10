# SPDX-License-Identifier: 0BSD
import io
import json
from pathlib import Path
import tempfile
import unittest
from generated_backup import catalog, groups, make_volume, restore, GitHub


class BackupTests(unittest.TestCase):
    def test_deduplicated_roundtrip_and_changed_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root/'source'; source.mkdir()
            (source/'a').write_bytes(b'terrain'*500)
            (source/'b').write_bytes(b'terrain'*500)
            (source/'empty').mkdir()
            manifest = root/'catalog.json'
            record = catalog(dict(roots={'project': str(source)}), manifest)
            self.assertEqual(record['logical_bytes'], record['unique_bytes']*2)
            rows = list(groups(record))[0]
            self.assertEqual(len(rows), 1)
            with io.BytesIO() as buffer:
                result = make_volume(record, rows, buffer)
                (root/'objects-001.zip').write_bytes(buffer.getvalue())
                self.assertEqual(result['bytes'], len(buffer.getvalue()))
            output = root/'restored'
            self.assertEqual(restore(manifest, root, output)['files'], 2)
            self.assertEqual((output/'project/a').read_bytes(), b'terrain'*500)
            self.assertTrue((output/'project/empty').is_dir())
            with self.assertRaises(FileExistsError): restore(manifest, root, output)
            (source/'b').write_bytes(b'new content')
            with self.assertRaises(ValueError): make_volume(record, rows, io.BytesIO())

    def test_credentials_block_publication_and_caches_are_excluded(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary); source=root/'source'; source.mkdir()
            (source/'.godot').mkdir(); (source/'.godot/cache').write_bytes(b'cache')
            (source/'.env').write_text('private')
            (source/'result.log').write_text('ghp_'+'a'*40)
            with self.assertRaisesRegex(ValueError,'Credential-like content'):
                catalog(dict(roots={'project':str(source)}),root/'catalog.json')
            (source/'result.log').write_text('safe')
            record=catalog(dict(roots={'project':str(source)}),root/'catalog.json')
            self.assertEqual(len(record['files']),1)
            self.assertEqual(len(record['exclusions']),2)

    def test_remote_verification_fails_closed(self):
        api=object.__new__(GitHub)
        api.request=lambda path: dict(state='uploaded',size=5,digest='sha256:'+'a'*64)
        api.verify_asset({'id':1},dict(bytes=5,sha256='a'*64))
        with self.assertRaises(ValueError): api.verify_asset({'id':1},dict(bytes=5,sha256='b'*64))


if __name__=='__main__': unittest.main()
