# SPDX-License-Identifier: 0BSD
import copy
import hashlib
import struct
import unittest
import world_inspector as inspector


def fixture():
    places = struct.pack('<6I',0x31524754,1,1703,33,1,1)
    places += struct.pack('<IfffII',3000,740.,48.,620.,5,6)+b'Flats'+b'A home'
    places += struct.pack('<7f',700,48,600,750,48,600,6)
    return inspector.encode({'terrain':b'opaque native terrain bytes',
        'future_component':bytes(range(256)), 'generated_region':places,
        'world_recipe_v1':struct.pack('<11I',0x31504352,8,1,7,1,2,1,3,1,0,1)})


class InspectorTests(unittest.TestCase):
    def test_roundtrip_preserves_all_native_sections(self):
        data=fixture();parts=inspector.decode(data)
        self.assertEqual(inspector.encode({name:payload for name,(_,payload) in parts.items()}),data)
        report=inspector.describe(data,True)
        self.assertEqual(report['container_integrity'],'passed')
        self.assertEqual(next(row for row in report['sections'] if row['name']=='generated_region')['decoded']['roads'][0]['width'],6)

    def test_both_supported_legacy_and_current_recipes(self):
        for values,version in [([0,2,1,0,1],1),([0,2,1,0,1,0],2),([1,3,3,2,1,3,1],6),([1,7,1,2,1,3,1,0,1],8)]:
            data=struct.pack('<'+'I'*(len(values)+2),0x31504352,version,*values)
            self.assertEqual(inspector.recipe(data)['version'],version)
            document={'schema':'terraforest.recipe.v1','options':dict(zip(inspector.RECIPE_FIELDS,values))}
            self.assertEqual(inspector.compile_recipe(document),data)
        with self.assertRaises(ValueError):inspector.recipe(struct.pack('<7I',0x31504352,1,0,7,1,0,1))

    def test_json_recipe_cannot_coerce_or_hide_unknown_fields(self):
        options=dict(biome=0,settlements=2,districts=1,network=0,trails=1)
        for changes in ({'biome':True},{'settlements':2.0},{'trails':-1},{'future_flag':1},{'settlements':7}):
            with self.assertRaises(ValueError):inspector.compile_recipe({'schema':'terraforest.recipe.v1','options':options|changes})

    def test_label_change_preserves_geometry_unknown_data_and_ids(self):
        before=fixture();labels=inspector.labels_document(before)
        self.assertEqual(inspector.replace_labels(before,labels),before)
        labels['places'][0]['title']='Courtyard flats'
        after=inspector.replace_labels(before,labels)
        left,right=inspector.decode(before),inspector.decode(after)
        for name in left:
            if name!='generated_region':self.assertEqual(left[name][1],right[name][1])
        a,b=inspector.region(left['generated_region'][1]),inspector.region(right['generated_region'][1])
        self.assertEqual(a['roads'],b['roads']);self.assertEqual(a['places'][0]['position'],b['places'][0]['position'])
        self.assertEqual(b['places'][0]['id'],3000)
        self.assertEqual(b['places'][0]['title'],'Courtyard flats')

    def test_mutations_fail_closed(self):
        data=fixture()
        for at in (0,8,12,16,47,48,len(data)-1):
            corrupt=bytearray(data);corrupt[at]^=1
            with self.assertRaises(ValueError):inspector.decode(corrupt)
        for cut in (0,7,47,48,len(data)-1):
            with self.assertRaises(ValueError):inspector.decode(data[:cut])
        with self.assertRaises(ValueError):inspector.decode(data+b'\0')

    def test_digest_does_not_bypass_structural_validation(self):
        original=fixture()
        for at,value in ((48,0xffffffff),(52,0xffffffff)):
            data=bytearray(original);struct.pack_into('<I',data,at,value)
            h=hashlib.sha256(data[8:16]);h.update(data[48:]);data[16:48]=h.digest()
            with self.assertRaises(ValueError):inspector.decode(data)

    def test_editor_rejects_stale_and_structural_changes(self):
        data=fixture();original=inspector.labels_document(data)
        changed=[]
        d=copy.deepcopy(original);d['source_sha256']='0'*64;changed.append(d)
        d=copy.deepcopy(original);d['places'][0]['id']=4;changed.append(d)
        d=copy.deepcopy(original);d['places'][0]['position']=[0,0,0];changed.append(d)
        d=copy.deepcopy(original);d['places'][0]['title']='x'*97;changed.append(d)
        d=copy.deepcopy(original);d['places'][0]['detail']='\x00';changed.append(d)
        d=copy.deepcopy(original);d['places']=[];changed.append(d)
        for document in changed:
            with self.assertRaises(ValueError):inspector.replace_labels(data,document)

    def test_region_semantics_are_checked(self):
        parts=inspector.decode(fixture());source=bytes(parts['generated_region'][1])
        for offset,raw in ((12,struct.pack('<I',99)),(28,struct.pack('<f',float('nan'))),(len(source)-4,struct.pack('<f',0))):
            data=bytearray(source);data[offset:offset+4]=raw
            with self.assertRaises(ValueError):inspector.region(data)


if __name__=='__main__':
    unittest.main()
