# SPDX-License-Identifier: 0BSD
import hashlib
from pathlib import Path
import sys,tempfile,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from clone_world import clone_once
class CacheCloneTests(unittest.TestCase):
 def test_valid_cache_follows_clone_but_existing_save_is_untouched(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp)/"worlds";root.mkdir();(root/"source.trw").write_bytes(b"world")
   folder=root.parent/"cartography"/"edited";folder.mkdir(parents=True)
   header=b"TFEDIT01"+bytes(32);pixels=bytes(262144);data=header+hashlib.sha256(header+pixels).digest()+pixels
   source=folder/(hashlib.sha256(b"source").hexdigest()+".bin");source.write_bytes(data)
   result=clone_once(root,"source","copy");self.assertTrue(result["map_cache_copied"])
   dest=folder/(hashlib.sha256(b"copy").hexdigest()+".bin");self.assertEqual(dest.read_bytes(),data)
   dest.write_bytes(b"existing");self.assertFalse(clone_once(root,"source","copy")["created"]);self.assertEqual(dest.read_bytes(),b"existing")
 def test_clone_cache_retention_is_bounded_and_ignores_unrelated_files(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp)/"worlds";root.mkdir();(root/"source.trw").write_bytes(b"world")
   folder=root.parent/"cartography"/"edited";folder.mkdir(parents=True)
   header=b"TFEDIT01"+bytes(32);pixels=bytes(262144);data=header+hashlib.sha256(header+pixels).digest()+pixels
   for i in range(64):(folder/(hashlib.sha256(str(i).encode()).hexdigest()+".bin")).write_bytes(b"old")
   (folder/(hashlib.sha256(b"source").hexdigest()+".bin")).write_bytes(data)
   unrelated=folder/"notes.bin";unrelated.write_bytes(b"keep")
   self.assertTrue(clone_once(root,"source","copy")["map_cache_copied"])
   self.assertEqual(len([p for p in folder.glob("*.bin") if len(p.stem)==64]),64)
   self.assertEqual(unrelated.read_bytes(),b"keep")
 def test_bad_cache_does_not_prevent_world_clone(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp)/"worlds";root.mkdir();(root/"source.trw").write_bytes(b"world")
   folder=root.parent/"cartography"/"edited";folder.mkdir(parents=True)
   (folder/(hashlib.sha256(b"source").hexdigest()+".bin")).write_bytes(b"TFEDIT01"+bytes(262208))
   result=clone_once(root,"source","copy");self.assertTrue(result["created"]);self.assertFalse(result["map_cache_copied"])
   self.assertEqual((root/"copy.trw").read_bytes(),b"world")
if __name__=="__main__":unittest.main()
