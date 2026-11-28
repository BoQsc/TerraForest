# SPDX-License-Identifier: 0BSD
import contextlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import run_generation_lab as target
from retained_artifacts import digest


class LaboratoryRetentionTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory();self.addCleanup(self.temporary.cleanup)
        self.root=Path(self.temporary.name);self.family=self.root/'reports/generation_lab';self.family.mkdir(parents=True)
        for name in ('001','002','003'):
            folder=self.family/name;folder.mkdir();(folder/'view.png').write_bytes(b'owned laboratory image '+name.encode())
            (folder/'run.json').write_text(json.dumps({'purpose':'native-landform-lab-v1','completed':True,'owned_outputs':{'view.png':digest(folder/'view.png')}}))
        (self.family/'001'/'user_note.txt').write_text('Do not delete unknown evidence')
        self.addCleanup(patch.stopall)
        patch.object(target,'ROOT',self.root).start();patch.object(target,'FAMILY',self.family).start()
        patch.object(target,'lease',lambda _path:contextlib.nullcontext()).start()

    def test_only_receipt_owned_old_output_retires(self):
        target.maintain()
        self.assertFalse((self.family/'001/view.png').exists())
        self.assertTrue((self.family/'001/outputs.archive.json').is_file())
        self.assertTrue((self.family/'001/user_note.txt').exists())
        self.assertTrue((self.family/'002/view.png').exists())
        self.assertTrue((self.family/'003/view.png').exists())

    def test_pin_prevents_retirement(self):
        (self.family/'001/.retain').write_text('Human review')
        target.maintain()
        self.assertTrue((self.family/'001/view.png').exists())

    def test_changed_evidence_is_preserved(self):
        (self.family/'001/view.png').write_bytes(b'later change')
        with self.assertRaises(ValueError):target.maintain()
        self.assertTrue((self.family/'001/view.png').exists())


if __name__=='__main__':unittest.main()
