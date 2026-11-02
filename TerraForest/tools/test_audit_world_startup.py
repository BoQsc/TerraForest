# SPDX-License-Identifier: 0BSD
import hashlib
import struct
import unittest
from audit_world_startup import sections


def archive(items):
    body = b"".join(struct.pack("<II", len(k), len(v)) + k + v for k, v in items)
    header = struct.pack("<II", 1, len(items))
    return b"TFWORLD1" + header + hashlib.sha256(header + body).digest() + body


class ArchiveAuditTests(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(sections(archive([(b"terrain", b"TFTR"), (b"water", b"123")])),
                         {"terrain": b"TFTR", "water": b"123"})

    def test_corruption(self):
        data = archive([(b"terrain", b"abc")])
        with self.assertRaises(ValueError):
            sections(data[:-1] + b"z")

    def test_missing_terrain(self):
        with self.assertRaises(ValueError):
            sections(archive([(b"water", b"abc")]))

    def test_duplicate_and_unsorted(self):
        for names in ((b"terrain", b"terrain"), (b"water", b"terrain")):
            with self.subTest(names=names), self.assertRaises(ValueError):
                sections(archive([(name, b"abc") for name in names]))

    def test_authenticated_bad_bounds(self):
        data = bytearray(archive([(b"terrain", b"abc")]))
        struct.pack_into("<I", data, 52, 9999)
        data[16:48] = hashlib.sha256(data[8:16] + data[48:]).digest()
        with self.assertRaises(ValueError):
            sections(bytes(data))

    def test_authenticated_trailing_bytes(self):
        data = bytearray(archive([(b"terrain", b"abc")]) + b"extra")
        data[16:48] = hashlib.sha256(data[8:16] + data[48:]).digest()
        with self.assertRaises(ValueError):
            sections(bytes(data))


if __name__ == "__main__":
    unittest.main()
