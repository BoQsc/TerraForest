# SPDX-License-Identifier: 0BSD
"""Inspect the native TFWORLD1 container; JSON is an inspection/editing view only.

Root integrity is checked independently of Godot. Component semantic validation
currently covers generated-region metadata and recipe records. Companion stores
and other component schemas still require the engine's complete restore validator.
"""
import argparse
import base64
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import uuid

LIMIT = 256 * 1024**2
SECTION_LIMIT = 64 * 1024**2
NAME = re.compile(r'[a-z0-9_]{1,48}\Z')
RECIPE_FIELDS = ('biome', 'settlements', 'districts', 'network', 'trails',
                 'road_grid', 'material_veins', 'introduction', 'profile')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def decode(data):
    """Match NativeWorldArchive's bounds, sorted-name and SHA-256 contract."""
    if not 48 <= len(data) <= LIMIT or data[:8] != b'TFWORLD1':
        raise ValueError('Not a bounded TFWORLD1 root container')
    version, count = struct.unpack_from('<II', data, 8)
    if version != 1 or not 1 <= count <= 128:
        raise ValueError('Unsupported container version or section count')
    digest = hashlib.sha256(data[8:16])
    digest.update(memoryview(data)[48:])
    if digest.digest() != data[16:48]:
        raise ValueError('Container checksum mismatch')
    at, previous, sections = 48, '', {}
    for _ in range(count):
        if at + 8 > len(data):
            raise ValueError('Truncated section header')
        size, length = struct.unpack_from('<II', data, at)
        at += 8
        if not 1 <= size <= 48 or at + size + length > len(data):
            raise ValueError('Invalid section bounds')
        name = data[at:at+size].decode('ascii')
        at += size
        if not NAME.fullmatch(name) or name <= previous or (name != 'terrain' and length > SECTION_LIMIT):
            raise ValueError('Invalid, duplicate, unordered or oversized section')
        sections[name] = (at, memoryview(data)[at:at+length])
        previous = name
        at += length
    if at != len(data) or 'terrain' not in sections:
        raise ValueError('Trailing bytes or missing terrain section')
    return sections


def encode(sections):
    if not 1 <= len(sections) <= 128 or 'terrain' not in sections:
        raise ValueError('Invalid section set')
    total = 48
    for name, payload in sections.items():
        if not NAME.fullmatch(name) or len(payload) > (LIMIT if name == 'terrain' else SECTION_LIMIT):
            raise ValueError('Invalid section')
        total += 8 + len(name) + len(payload)
    if total > LIMIT:
        raise ValueError('Container budget exceeded')
    out = bytearray(b'TFWORLD1' + struct.pack('<II', 1, len(sections)) + bytes(32))
    for name in sorted(sections):
        payload = sections[name]
        out += struct.pack('<II', len(name), len(payload)) + name.encode('ascii')
        out += payload
    digest = hashlib.sha256(out[8:16]); digest.update(memoryview(out)[48:])
    out[16:48] = digest.digest()
    return bytes(out)


def read(path):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or path.stat().st_size > LIMIT:
        raise ValueError('Expected a regular bounded root file')
    with path.open('rb') as stream:
        data = stream.read(LIMIT + 1)
    decode(data)
    return data


def recipe(data):
    if not data:
        return None
    if len(data) not in (28, 32, 36, 40, 44):
        raise ValueError('Invalid recipe size')
    words = struct.unpack('<' + 'I' * (len(data)//4), data)
    magic, version, *values = words
    if magic != 0x31504352:
        raise ValueError('Invalid recipe magic')
    expected = {28: (1,), 32: ((values[5]+1 if len(values)>5 and values[5]>=2 else 2),),
                36: (5, 6), 40: (7,), 44: ((9 if len(values)==9 and values[8]==2 else 8),)}
    if version not in expected[len(data)] or (len(values) >= 6 and values[5] > 3) or any(v > 1 for v in values[6:8]) or (len(values)==9 and values[8]>2):
        raise ValueError('Unsupported recipe version or flags')
    biome, settlements, districts, network, trails = values[:5]
    if len(values) == 9 and values[8] in (1,2):
        valid = biome <= 2 and settlements == 7 and districts == 1 and (values[8]!=2 or values[7]==0) and network <= 2 and trails <= 2
    else:
        expanded = version >= 6
        valid = (biome <= 2 and 1 <= settlements <= 3 and 1 <= districts <= (3 if expanded else 2)
                 and settlements*districts <= (9 if expanded else 6) and network <= (2 if expanded else 1) and trails <= 2)
    if not valid:
        raise ValueError('Invalid recipe fields')
    return {'version': version, 'options': dict(zip(RECIPE_FIELDS, values))}


def compile_recipe(document):
    if not isinstance(document,dict) or set(document)!={'schema','options'} or document['schema']!='terraforest.recipe.v1':
        raise ValueError('Expected terraforest.recipe.v1 with options')
    options=document['options']
    if not isinstance(options,dict) or not 5<=len(options)<=9 or set(options)!=set(RECIPE_FIELDS[:len(options)]):
        raise ValueError('Unsupported recipe option set')
    values=[options[name] for name in RECIPE_FIELDS[:len(options)]]
    if any(type(value) is not int or not 0<=value<=8 for value in values):
        raise ValueError('Recipe fields must be bounded integers')
    count=len(values)
    version=1 if count==5 else 2
    if count==6 and values[5]>=2:version=values[5]+1
    if count==7:version=6 if values[2]>2 or values[3]>1 else 5
    if count==8:version=7
    if count==9:version=9 if values[8]==2 else 8
    data=struct.pack('<'+'I'*(count+2),0x31504352,version,*values)
    recipe(data)
    return data


def region(data):
    if not data:
        return None
    if not 24 <= len(data) <= 512*1024:
        raise ValueError('Invalid generated-region size')
    magic, version, seed, generator, count, road_count = struct.unpack_from('<6I', data)
    if magic != 0x31524754 or version != 1 or seed > 0x7fffffff or not 17 <= generator <= 36 or count > 256 or road_count > 8192:
        raise ValueError('Unsupported generated-region header')
    def position(p):
        return all(math.isfinite(v) for v in p) and 0 <= p[0] <= 2000 and 0 <= p[1] <= 250 and 0 <= p[2] <= 2000
    at, places, ids = 24, [], set()
    for _ in range(count):
        if at + 24 > len(data):
            raise ValueError('Truncated place')
        identity, x, y, z, title_size, detail_size = struct.unpack_from('<IfffII', data, at)
        at += 24
        if identity in ids or not position((x,y,z)) or not 1 <= title_size <= 96 or not 1 <= detail_size <= 192 or at+title_size+detail_size > len(data):
            raise ValueError('Invalid place')
        strings = []
        for size in (title_size, detail_size):
            raw = bytes(data[at:at+size]); at += size
            if any(c < 32 or c > 126 for c in raw):
                raise ValueError('Place labels must be printable ASCII')
            strings.append(raw.decode('ascii'))
        places.append({'id': identity, 'position': [x,y,z], 'title': strings[0], 'detail': strings[1]}); ids.add(identity)
    if at + road_count*28 != len(data):
        raise ValueError('Invalid road table size')
    roads = []
    for _ in range(road_count):
        a, b, width = struct.unpack_from('<3f', data, at), struct.unpack_from('<3f', data, at+12), struct.unpack_from('<f', data, at+24)[0]
        at += 28
        if not position(a) or not position(b) or math.dist(a,b) < .05 or not math.isfinite(width) or not 1 <= width <= 64:
            raise ValueError('Invalid road')
        roads.append({'a': list(a), 'b': list(b), 'width': width})
    return {'version': version, 'seed': seed, 'generator': generator, 'places': places, 'roads': roads}


def describe(data, full=False):
    sections = decode(data)
    result = {'format': 'TFWORLD1', 'version': 1, 'bytes': len(data), 'sha256': sha(data), 'container_integrity': 'passed',
              'scope': 'Root envelope plus supported metadata schemas. Companion stores and other component semantics require engine restore validation.', 'sections': []}
    for name, (offset, payload) in sections.items():
        row = {'name': name, 'offset': offset, 'bytes': len(payload), 'sha256': sha(payload), 'semantic_validation': 'not implemented'}
        if name in ('world_recipe_v1', 'generated_region'):
            value = recipe(payload) if name == 'world_recipe_v1' else region(payload)
            row['semantic_validation'] = 'passed'
            if name == 'generated_region' and value and not full:
                value = {**value, 'places': len(value['places']), 'roads': len(value['roads'])}
            row['decoded'] = value
        result['sections'].append(row)
    return result


def labels_document(data):
    sections = decode(data)
    value = region(sections['generated_region'][1]) if 'generated_region' in sections else None
    if value is None:
        raise ValueError('No generated place labels')
    return {'schema': 'terraforest.place-labels.v1', 'source_sha256': sha(data),
            'places': [{k:p[k] for k in ('id','title','detail')} for p in value['places']]}


def replace_labels(data, document):
    original = labels_document(data)
    if not isinstance(document, dict) or set(document) != set(original) or document['schema'] != original['schema'] or document['source_sha256'] != original['source_sha256']:
        raise ValueError('Wrong label schema, extra fields or stale source fingerprint')
    rows = document['places']
    if not isinstance(rows,list) or len(rows) != len(original['places']):
        raise ValueError('Label edits must retain the complete place ID set')
    edits = {}
    for row in rows:
        if not isinstance(row,dict) or set(row) != {'id','title','detail'} or type(row['id']) is not int or row['id'] in edits:
            raise ValueError('Invalid or duplicate label row')
        for field, limit in (('title',96),('detail',192)):
            text = row[field]
            if not isinstance(text,str) or not 1 <= len(text) <= limit or any(ord(c)<32 or ord(c)>126 for c in text):
                raise ValueError('Invalid '+field)
        edits[row['id']] = row
    sections = decode(data); payload = sections['generated_region'][1]; value = region(payload)
    if set(edits) != {p['id'] for p in value['places']}:
        raise ValueError('Place IDs cannot change through label editing')
    output = bytearray(payload[:24]); old_at = 24
    for place in value['places']:
        _, _, _, _, title_size, detail_size = struct.unpack_from('<IfffII',payload,old_at)
        # Retain position/id bytes exactly, including signed zero encodings.
        output += payload[old_at:old_at+16]
        row = edits[place['id']]; title, detail = row['title'].encode('ascii'), row['detail'].encode('ascii')
        output += struct.pack('<II',len(title),len(detail)) + title + detail
        old_at += 24+title_size+detail_size
    output += payload[old_at:]
    region(output)
    return encode({name:(output if name=='generated_region' else part) for name,(_,part) in sections.items()})


def write_new(path, data):
    """Explicit outputs never overwrite an existing path."""
    with Path(path).open('xb') as stream:
        stream.write(data); stream.flush(); os.fsync(stream.fileno())


def apply_labels(path, document):
    """Use the same exclusive Windows root lease as the native save publisher."""
    from cleanup_generation_copies import lease, ordinary
    path = Path(path).absolute(); ordinary(path)
    with lease(path):
        before = read(path); after = replace_labels(before,document)
        if after == before:
            return {'changed': False, 'sha256':sha(before)}
        identity = f'.inspector.{os.getpid()}.{uuid.uuid4().hex}'
        backup, pending = Path(str(path)+identity+'.backup'), Path(str(path)+identity+'.pending')
        write_new(backup,before)
        write_new(pending,after)
        if read(backup) != before or read(pending) != after or read(path) != before:
            raise ValueError('Publication verification failed; source and recovery files retained')
        # Keep every companion store in place and every untouched section byte.
        import ctypes
        kernel = ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.MoveFileExW.argtypes=[ctypes.c_wchar_p,ctypes.c_wchar_p,ctypes.c_uint32]
        kernel.MoveFileExW.restype=ctypes.c_int
        if not kernel.MoveFileExW(str(pending),str(path),1|8):
            raise OSError(ctypes.get_last_error(),'Atomic publication failed; backup and pending retained')
        return {'changed':True,'before_sha256':sha(before),'sha256':sha(after),'backup':str(backup),'changed_sections':['generated_region']}


def native_check(path, engine=None):
    """Receipt-owned, headless integrity check; no world copy/build/export."""
    from datetime import datetime, timezone
    from development_storage import ROOT, admit
    from run_godot_check import execute
    path=Path(path).absolute()
    admission=admit(report_bytes=2*1024**2,world_bytes=0,scratch_bytes=0)
    folder=ROOT/'reports/world_inspector'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True,exist_ok=False)
    command=[str(engine or ROOT/'TerraForest.exe'),'--headless','--path',str(ROOT),
             '--log-file',str(folder/'engine.log'),'--script','res://tools/world_inspector_native.gd','--',
             '--world-root='+str(path),'--inspection-output='+str(folder/'inspection.json')]
    before=sha(read(path))
    receipt={'command':command,'admission':admission,'source_sha256':before,
             'lifecycle':'At most 2MiB of logs, validation JSON and receipt; no world copy, build, export or generated geometry. Small completed and failed evidence remains with the receipt.',
             'scope':'Current generated regional world storage and referenced companions; semantic scope is reported by the native verifier.'}
    (folder/'run.json').write_text(json.dumps(receipt,indent=2))
    result=execute(command,folder,120,'WORLD_INSPECTOR_NATIVE ok=true')
    receipt['result']=result;receipt['source_unchanged']=sha(read(path))==before
    (folder/'run.json').write_text(json.dumps(receipt,indent=2))
    if not result['passed'] or not receipt['source_unchanged']:
        raise ValueError('Native check failed; retained receipt: '+str(folder/'run.json'))
    return {'ok':True,'report':str(folder/'run.json'),'native':json.loads((folder/'inspection.json').read_text())}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command',required=True)
    for name in ('inspect','verify','export-labels','apply-labels','extract','diff','native-check','export-recipe','compile-recipe'):
        item=sub.add_parser(name);item.add_argument('world',type=Path,metavar='RECIPE_JSON' if name=='compile-recipe' else 'WORLD')
        if name=='inspect':item.add_argument('--full',action='store_true')
        if name in ('export-labels','extract','export-recipe','compile-recipe'):item.add_argument('--output',type=Path,required=True)
        if name=='extract':item.add_argument('--section',required=True)
        if name=='apply-labels':item.add_argument('json',type=Path)
        if name=='diff':item.add_argument('other',type=Path)
        if name=='native-check':item.add_argument('--godot',type=Path)
    args=parser.parse_args(argv)
    try:
        if args.command=='compile-recipe':
            if args.world.stat().st_size>16384:raise ValueError('Recipe document too large')
            data=compile_recipe(json.loads(args.world.read_text(encoding='utf-8')));write_new(args.output,data)
            result={'output':str(args.output),'bytes':len(data),'sha256':sha(data),'argument':'--world-recipe='+base64.b64encode(data).decode('ascii')}
        elif args.command=='native-check':result=native_check(args.world,args.godot)
        elif args.command=='apply-labels':
            if args.json.stat().st_size>128*1024:raise ValueError('Label document too large')
            result=apply_labels(args.world,json.loads(args.json.read_text(encoding='utf-8')))
        else:
            data=read(args.world)
            if args.command in ('inspect','verify'):result=describe(data,getattr(args,'full',False))
            elif args.command=='export-labels':
                write_new(args.output,(json.dumps(labels_document(data),indent=2)+'\n').encode());result={'output':str(args.output)}
            elif args.command=='export-recipe':
                value=recipe(decode(data)['world_recipe_v1'][1])
                if value is None:raise ValueError('No stored recipe')
                document={'schema':'terraforest.recipe.v1','options':value['options']}
                write_new(args.output,(json.dumps(document,indent=2)+'\n').encode());result={'output':str(args.output)}
            elif args.command=='extract':
                sections=decode(data)
                if args.section not in sections:raise ValueError('Unknown section')
                payload=sections[args.section][1];write_new(args.output,payload);result={'output':str(args.output),'bytes':len(payload),'sha256':sha(payload)}
            else:
                left,right=decode(data),decode(read(args.other))
                result={'changed_sections':[name for name in sorted(left.keys()|right.keys()) if name not in left or name not in right or left[name][1]!=right[name][1]]}
        print(json.dumps(result,indent=2));return 0
    except (OSError,ValueError,KeyError,UnicodeError,struct.error) as error:
        print(json.dumps({'ok':False,'error':str(error)}));return 1


if __name__=='__main__':
    raise SystemExit(main())
