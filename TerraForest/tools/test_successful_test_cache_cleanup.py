import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from prune_successful_test_caches import remove_owned_temporary_cache


class OwnedCacheTests(unittest.TestCase):
    def test_removes_only_the_named_owned_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            owned = root / ("first_person_world_" + "a" * 32)
            owned.mkdir()
            (owned / "derived.bin").write_bytes(b"temporary")
            worlds = root / "worlds"
            worlds.mkdir()
            (worlds / "played.trw").write_bytes(b"authoritative")
            remove_owned_temporary_cache("user://" + owned.name, root)
            self.assertFalse(owned.exists())
            self.assertEqual((worlds / "played.trw").read_bytes(), b"authoritative")

    def test_refuses_nonunique_or_escaping_names(self):
        with tempfile.TemporaryDirectory() as temporary:
            for value in ["user://worlds", "user://../worlds", "res://first_person_world_" + "a" * 32, "user://first_person_world_fake"]:
                with self.subTest(value=value), self.assertRaises(ValueError):
                    remove_owned_temporary_cache(value, Path(temporary))

    def test_missing_owned_cache_is_an_idempotent_noop(self):
        with tempfile.TemporaryDirectory() as temporary:
            self.assertIsNone(remove_owned_temporary_cache("user://first_person_world_" + "a" * 32, Path(temporary)))


if __name__ == "__main__":
    unittest.main()
