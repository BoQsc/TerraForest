# SPDX-License-Identifier: 0BSD
import json
import os
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from retained_artifacts import Store, archive, digest, load_manifest, restore, retire, relative_name, verify
from maintain_performance_artifacts import world_candidates, build_candidates, owned_lease, archive_regional_cache


class RetainedArtifactsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'source'; self.source.mkdir()
        self.store = Store(self.root / 'store')
        self.manifest = self.root / 'evidence' / 'world.archive.json'
        self.provenance = dict(owner='unit-test', kind='world')

    def capture(self):
        return archive(self.source, [p.name for p in self.source.iterdir()], self.manifest, self.store, self.provenance)

    def test_roundtrip_chunk_sharing_empty_files_and_directories(self):
        (self.source / 'empty').mkdir()
        (self.source / 'zero').touch()
        data = b'world payload' * 90000
        for name in ('one.trw', 'two.trw'):
            (self.source / name).write_bytes(data)
        record = self.capture()
        self.assertEqual(record['files'][0]['chunks'], record['files'][1]['chunks'])
        before = self.store.bytes
        verify(record, self.store)
        self.assertEqual(retire(record, self.store, self.source), len(data) * 2)
        output = self.root / 'restored'
        self.assertEqual(restore(self.manifest, self.store, output)['files'], 3)
        self.assertEqual((output / 'one.trw').read_bytes(), data)
        self.assertEqual((output / 'two.trw').read_bytes(), data)
        self.assertTrue((output / 'empty').is_dir())
        self.assertEqual((output / 'zero').stat().st_size, 0)
        self.assertEqual(self.store.bytes, before)

    def test_corruption_prevents_retirement_and_restore(self):
        path = self.source / 'save.trw'; path.write_bytes(b'precious data')
        record = self.capture()
        key = record['files'][0]['chunks'][0]
        (self.store.path / key[:2] / (key + '.z')).write_bytes(b'broken')
        for operation in (lambda:retire(record, self.store, self.source),
                          lambda:restore(self.manifest, self.store, self.root / 'out')):
            with self.assertRaises(Exception):
                operation()
        self.assertEqual(path.read_bytes(), b'precious data')
        self.assertFalse((self.root / 'out').exists())

    def test_modified_source_retains_entire_batch(self):
        for name in ('a', 'b'):
            (self.source / name).write_bytes(b'original')
        record = self.capture()
        (self.source / 'b').write_bytes(b'new save')
        with self.assertRaisesRegex(ValueError, 'Changed source'):
            retire(record, self.store, self.source)
        self.assertEqual((self.source / 'a').read_bytes(), b'original')
        self.assertEqual((self.source / 'b').read_bytes(), b'new save')

    def test_store_budget_never_removes_source(self):
        (self.source / 'save').write_bytes(os.urandom(100))
        self.store.budget = 1
        with self.assertRaisesRegex(OSError, 'budget'):
            self.capture()
        self.assertTrue((self.source / 'save').exists())
        self.assertFalse(self.manifest.exists())

    def test_low_storage_never_removes_source(self):
        (self.source / 'save').write_bytes(b'original')
        with patch('retained_artifacts.require_free_space', side_effect=OSError('disk reserve')):
            with self.assertRaises(OSError):
                self.capture()
        self.assertTrue((self.source / 'save').exists())
        self.assertFalse(self.manifest.exists())

    def test_restore_refuses_existing_destination(self):
        (self.source / 'save').write_bytes(b'original')
        self.capture()
        with self.assertRaises(FileExistsError):
            restore(self.manifest, self.store, self.source)
        self.assertEqual((self.source / 'save').read_bytes(), b'original')

    def test_unsafe_paths_and_wrong_retirement_root_refused(self):
        for name in ('../world', '/save', 'C:/save', 'nested/../save', 'nested\\save'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                relative_name(name)
        (self.source / 'save').write_bytes(b'original')
        record = self.capture()
        with self.assertRaises(ValueError):
            retire(record, self.store, self.root)
        self.assertTrue((self.source / 'save').exists())

    def test_interrupted_retirement_can_resume_and_restore(self):
        for name in ('a', 'b'):
            (self.source / name).write_bytes(name.encode())
        self.capture()
        (self.source / 'a').unlink()  # Simulate a prior verified retirement interruption.
        record = self.capture()
        self.assertEqual(retire(record, self.store, self.source), 1)
        restore(self.manifest, self.store, self.root / 'restored')
        self.assertEqual((self.root / 'restored/a').read_bytes(), b'a')

    def test_symlink_is_never_followed(self):
        outside = self.root / 'protected'; outside.write_bytes(b'user save')
        try:
            (self.source / 'linked').symlink_to(outside)
        except OSError:
            self.skipTest('Host does not permit creating symlinks')
        with self.assertRaisesRegex(ValueError, 'Linked'):
            self.capture()
        self.assertEqual(outside.read_bytes(), b'user save')

    def test_receipt_ownership_sources_recent_modified_and_unknown_worlds(self):
        worlds = self.root / 'worlds'; worlds.mkdir()
        base = self.root / 'reports/performance_changes'; base.mkdir(parents=True)
        source = 'StartupBench_FPS_20261109T073252'
        (worlds / (source + '.trw')).write_bytes(b'fixture')
        slots = []
        for i in range(7):
            slot = 'StartupBench_FPS_20261110T08000' + str(i)
            slots.append(slot)
            (worlds / (slot + '.trw')).write_bytes(b'test')
            folder = base / str(i); folder.mkdir()
            (folder / 'run.json').write_text(json.dumps(dict(
                clone=dict(created=True, slot=slot, source_slot=source), result=dict(exit_code=0),
                command=['engine', 'frame_trace_world.gd', '--trace-world-slot=' + slot])))
        # An apparent test name without ownership proof remains a save.
        unknown = worlds / 'StartupBench_FPS_20261110T099999.trw'; unknown.write_bytes(b'unknown')
        (worlds / (slots[1] + '.retain')).touch()
        os.utime(worlds / (slots[2] + '.trw'), ns=(10**19, 10**19))
        (worlds / (slots[3] + '.custom')).write_bytes(b'unknown sidecar')
        rows, retained = world_candidates(self.root, worlds, keep=2)
        self.assertEqual([r['slot'] for r in rows], [slots[0], slots[4]])
        self.assertTrue(unknown.exists())
        self.assertTrue((worlds / (source + '.trw')).exists())

    @unittest.skipUnless(os.name == 'nt', 'Windows junction regression')
    def test_windows_junction_to_live_assets_is_rejected(self):
        protected = self.root / 'live_assets'; protected.mkdir()
        (protected / 'asset').write_bytes(b'protected asset')
        link = self.source / 'addons'
        subprocess.run(['cmd', '/c', 'mklink', '/J', str(link), str(protected)],
                       check=True, capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            with self.assertRaisesRegex(ValueError, 'Linked'):
                self.capture()
            self.assertEqual((protected / 'asset').read_bytes(), b'protected asset')
        finally:
            link.rmdir()  # Remove this known temporary junction, never its target.

    @unittest.skipUnless(os.name == 'nt', 'Windows save lease regression')
    def test_active_world_lease_prevents_second_owner(self):
        path = self.source / 'save.trw'; path.write_bytes(b'player save')
        with owned_lease(path, self.source):
            with self.assertRaises(OSError):
                with owned_lease(path, self.source):
                    self.fail('Acquired an already-owned world')
        self.assertEqual(path.read_bytes(), b'player save')

    def test_generated_startup_world_referenced_as_input_is_protected(self):
        worlds = self.root / 'worlds'; worlds.mkdir()
        base = self.root / 'reports/startup_optimization'; base.mkdir(parents=True)
        slots = ['StartupBench_' + str(i) * 16 for i in range(5)]
        for i, slot in enumerate(slots):
            (worlds / (slot + '.trw')).write_bytes(b'generated')
            folder = base / str(i); folder.mkdir()
            (folder / 'run.json').write_text(json.dumps(dict(slot=slot, result=dict(exit_code=0),
                command=['startup_benchmark.gd', '--benchmark-generate', '--benchmark-slot=' + slot])))
        folder = base / 'source_use'; folder.mkdir()
        (folder / 'run.json').write_text(json.dumps(dict(slot=slots[0], result=dict(exit_code=0),
            command=['startup_benchmark.gd', '--benchmark-slot=' + slots[0]])))
        rows, _ = world_candidates(self.root, worlds, keep=2)
        self.assertEqual([r['slot'] for r in rows], slots[1:3])

    def test_selection_resumes_world_without_canonical_file(self):
        worlds = self.root / 'worlds'; worlds.mkdir()
        slot = 'StartupBench_FPS_20261110T080000'
        folder = self.root / 'reports/performance_changes/run'; folder.mkdir(parents=True)
        report = folder / 'run.json'
        report.write_text(json.dumps(dict(clone=dict(created=True, slot=slot,
            source_slot='StartupBench_FPS_20261109T073252'), result=dict(exit_code=0),
            command=['frame_trace_world.gd', '--trace-world-slot=' + slot])))
        region = worlds / (slot + '.trw.regions'); region.mkdir()
        (region / 'region').write_bytes(b'terrain')
        self.assertEqual(world_candidates(self.root, worlds, keep=0)[0], [])
        (folder / 'world.archive.json').write_text('{}')
        self.assertEqual(len(world_candidates(self.root, worlds, keep=0)[0]), 1)
        (region / 'region').unlink(); region.rmdir()
        self.assertEqual(world_candidates(self.root, worlds, keep=0)[0], [])

    def test_selection_resumes_build_without_package(self):
        base = self.root / 'reports/startup_optimization'; base.mkdir(parents=True)
        build = base / 'frozen'; build.mkdir()
        (build / 'native.dll').write_bytes(b'library')
        hashes = {'TerraForest.pck': '0' * 64, 'native.dll': digest(build / 'native.dll')}
        (build / 'manifest.json').write_text(json.dumps(hashes))
        run = base / 'run'; run.mkdir()
        (run / 'run.json').write_text(json.dumps(dict(build_manifest=hashes,
            command=[str(build / 'TerraForest.pck')])))
        self.assertEqual(build_candidates(self.root), [])
        (build / 'build.archive.json').write_text('{}')
        self.assertEqual(len(build_candidates(self.root)), 1)
        (build / 'native.dll').unlink()
        self.assertEqual(build_candidates(self.root), [])

    def test_readonly_regional_cache_archives_failed_evidence_and_protects_source(self):
        stamp='20261110T100000123456Z'
        report=self.root/'reports/checks'/stamp/'run.json'; report.parent.mkdir(parents=True)
        userdata=self.root/'userdata'; userdata.mkdir()
        name='zombie_regional_'+stamp
        cache=userdata/name; cache.mkdir()
        (cache/'diagnostic.bin').write_bytes(b'failed test evidence')
        source=userdata/'player.trw'; source.write_bytes(b'player save')
        record=dict(command=['res://tests/zombie_regional_world.gd','--snapshot-readonly',
            '--derived-cache=user://'+name],result=dict(exit_code=1),source_data_unchanged=False)
        report.write_text(json.dumps(record))
        with patch('maintain_performance_artifacts.no_game_processes'):
            with self.assertRaises(ValueError): archive_regional_cache(report,self.root,userdata)
            record['source_data_unchanged']=True; report.write_text(json.dumps(record))
            result=archive_regional_cache(report,self.root,userdata)
        self.assertEqual(result['removed_bytes'],len(b'failed test evidence'))
        store=Store(self.root/'reports/retained_artifacts/chunks')
        restore(Path(result['manifest']),store,self.root/'restored_cache')
        self.assertEqual((self.root/'restored_cache/diagnostic.bin').read_bytes(),b'failed test evidence')
        self.assertEqual(source.read_bytes(),b'player save')

    def test_other_world_families_require_creation_proof_and_keep_recent_sources(self):
        worlds=self.root/'worlds';worlds.mkdir()
        slots=['Survival_1703_'+str(i)*8 for i in range(5)]
        for i,slot in enumerate(slots):
            (worlds/(slot+'.trw')).write_bytes(b'generated test save')
            folder=self.root/'reports/survival'/str(i);folder.mkdir(parents=True)
            (folder/'created_slot.json').write_text(json.dumps(dict(slot=slot)))
            command=['player_survival_world.gd','--session-evidence-dir='+folder.as_posix()]
            (folder/'run.json').write_text(json.dumps(dict(phases=[dict(phase='create',command=command,result=dict(exit_code=1))])))
        # A copied fixture protects the original even when its owner is old.
        folder=self.root/'reports/ride/0';folder.mkdir(parents=True)
        clone=dict(created=True,slot='TraderRide_abcdef123456',source_slot=slots[0])
        (folder/'world.json').write_text(json.dumps(clone))
        (folder/'run.json').write_text(json.dumps(dict(clone=clone,
            command=['trader_ride_world.gd','--session-evidence-dir='+folder.as_posix()],result=dict(exit_code=1))))
        # A slot-shaped name alone, or a receipt without its evidence argument,
        # cannot authorize retirement.
        unknown='Survival_1703_abcdef12'
        (worlds/(unknown+'.trw')).write_bytes(b'keep unknown')
        folder=self.root/'reports/unknown';folder.mkdir(parents=True)
        (folder/'created_slot.json').write_text(json.dumps(dict(slot=unknown)))
        (folder/'run.json').write_text(json.dumps(dict(phases=[dict(phase='create',command=['player_survival_world.gd'],result=dict(exit_code=0))])))
        # A played save must survive even when an old creation receipt exists.
        import time
        os.utime(worlds/(slots[1]+'.trw'),(time.time()+10,time.time()+10))
        rows,retained=world_candidates(self.root,worlds,keep=2)
        self.assertEqual([r['slot'] for r in rows],[slots[2]])
        self.assertTrue(rows[0]['ownership'])
        self.assertTrue(any(r['slot']==slots[1] and 'modified' in r['reason'] for r in retained))
        # After a family has been inactive for three days its unmodified ready
        # copies can become cold evidence. Source fixtures remain protected.
        old=time.time()-4*86400
        for slot in slots:
            if slot!=slots[1]:os.utime(worlds/(slot+'.trw'),(old-60,old-60))
        for report in (self.root/'reports/survival').glob('*/run.json'):
            os.utime(report,(old,old))
        rows,_=world_candidates(self.root,worlds,keep=2)
        self.assertEqual({r['slot'] for r in rows},set(slots[2:]))


if __name__ == '__main__':
    unittest.main()
