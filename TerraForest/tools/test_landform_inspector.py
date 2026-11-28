# SPDX-License-Identifier: 0BSD
import struct
import unittest
from landform_inspector import inspect


def seal(data):
    value=14695981039346656037
    for byte in data:value=((value^byte)*1099511628211)&((1<<64)-1)
    return data+struct.pack('<Q',value)


def fixture():
    return seal(struct.pack('<IIIfffII',0x3150464c,1,1703,768,64,40,1,0)+
                struct.pack('<II10f',1,0,50,50,100,90,12,18,64,30,24,.1))


class LandformInspectorTests(unittest.TestCase):
    def test_kernel_version_is_explicit_and_unknown_versions_reject(self):
        data=bytearray(fixture()[:-8]);struct.pack_into('<I',data,4,2)
        self.assertEqual(inspect(seal(data))['kernel_version'],2)
        struct.pack_into('<I',data,4,3)
        self.assertEqual(inspect(seal(data))['kernel_version'],3)
        struct.pack_into('<I',data,4,4)
        with self.assertRaises(ValueError):inspect(seal(data))

    def test_explicit_portable_fields(self):
        result=inspect(fixture())
        self.assertEqual(result['seed'],1703)
        self.assertEqual(result['bytes'],88)
        self.assertEqual(result['segments'][0]['kind'],'ridge')
        self.assertEqual(result['segments'][0]['end'],[100,90,18])

    def test_corruption_and_truncation_are_rejected(self):
        source=fixture()
        for offset in (0,4,8,20,24,28,32,len(source)-1):
            changed=bytearray(source);changed[offset]^=1
            with self.assertRaises(ValueError):inspect(changed)
        for size in (0,8,39,87):
            with self.assertRaises(ValueError):inspect(source[:size])

    def test_resealed_bad_geometry_is_still_rejected(self):
        source=fixture()[:-8]
        for offset,form,value in [(28,'I',1),(32,'I',99),(36,'I',32),(40,'f',float('nan')),(56,'f',0),(64,'f',300),(72,'f',0)]:
            changed=bytearray(source);struct.pack_into('<'+form,changed,offset,value)
            with self.subTest(offset=offset),self.assertRaises(ValueError):inspect(seal(changed))

    def test_open_coast_is_rejected(self):
        changed=bytearray(fixture()[:-8]);struct.pack_into('<I',changed,32,0)
        with self.assertRaises(ValueError):inspect(seal(changed))


if __name__=='__main__':unittest.main()
