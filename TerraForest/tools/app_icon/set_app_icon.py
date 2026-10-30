# SPDX-License-Identifier: 0BSD
"""Replace a Windows executable's icon resources, preserving every other resource.

The usual post-link trick appends a fresh `.rsrc` section holding only
RT_ICON/RT_GROUP_ICON. On a Godot binary that silently drops RT_MANIFEST (DPI
awareness, comctl32 v6) and RT_VERSION, so this rebuilds the existing `.rsrc`
payload instead: icons come from the `.ico`, every other resource is copied byte
for byte with its type/name/language keys, and the icon group keeps its original
name. No section entry, RVA, SizeOfImage or file length changes, and re-running
the patch is idempotent.

Usage:
    python tools/app_icon/set_app_icon.py                  # patch the project executable
    python tools/app_icon/set_app_icon.py --check          # verify without writing
    python tools/app_icon/set_app_icon.py --exe dist/TerraForest.exe --icon other.ico
"""
from pathlib import Path
import argparse
import struct
import sys
import time

TOOL = Path(__file__).resolve().parent
ROOT = TOOL.parents[1]
# Local play build first, then the export path, then the older renamed copy.
CANDIDATE_EXES = (ROOT/'TerraForest.exe', ROOT/'Godot Engine TerraForest.exe',
                  ROOT/'dist/TerraForest.exe')
DEFAULT_ICON = TOOL/'terraforest.ico'
RT_ICON, RT_GROUP_ICON, RT_VERSION, RT_MANIFEST = 3, 14, 16, 24
LANG = 0x0409


def u16(data, offset): return struct.unpack_from('<H', data, offset)[0]
def u32(data, offset): return struct.unpack_from('<I', data, offset)[0]
def put32(data, offset, value): struct.pack_into('<I', data, offset, value)


def sections(data):
    """Section table entries plus the offset of the resource data directory."""
    if len(data) < 0x40 or data[:2] != b'MZ':
        raise SystemExit('not a PE executable')
    pe = u32(data, 0x3C)
    if data[pe:pe+4] != b'PE\0\0':
        raise SystemExit('not a PE executable')
    coff = pe + 4
    count, header_size = u16(data, coff + 2), u16(data, coff + 16)
    optional = coff + 20
    magic = u16(data, optional)
    if magic not in (0x10B, 0x20B):
        raise SystemExit('unsupported PE optional header')
    dir_base = optional + (112 if magic == 0x20B else 96)
    entries = []
    for index in range(count):
        at = optional + header_size + index * 40
        entries.append({'name': data[at:at+8].rstrip(b'\0').decode('ascii', 'replace'),
                        'header': at, 'vsize': u32(data, at + 8), 'rva': u32(data, at + 12),
                        'raw_size': u32(data, at + 16), 'raw': u32(data, at + 20)})
    return entries, dir_base + 2 * 8


def resource_section(data):
    entries, resource_dir = sections(data)
    found = [s for s in entries if s['name'] == '.rsrc']
    if not found:
        raise SystemExit('no .rsrc section: this executable carries no icon resources')
    return resource_dir, found[0]


def read_key(data, raw, field):
    if field & 0x80000000:
        at = raw + (field & 0x7FFFFFFF)
        return ('str', data[at+2:at+2+u16(data, at)*2].decode('utf-16-le'))
    return ('id', field)


def read_resources(data):
    """Flatten the resource tree into (keys, blob) pairs.

    Keys are ('id', n) or ('str', name) per level: type, name, language.
    """
    _, section = resource_section(data)
    raw, rva = section['raw'], section['rva']

    def walk(relative, keys):
        if len(keys) == 3:
            raise SystemExit('resource tree is deeper than type/name/language')
        base, found = raw + relative, []
        named, ids = u16(data, base + 12), u16(data, base + 14)
        for i in range(named + ids):
            at = base + 16 + i * 8
            key, target = read_key(data, raw, u32(data, at)), u32(data, at + 4)
            if target & 0x80000000:
                found.extend(walk(target & 0x7FFFFFFF, keys + [key]))
                continue
            entry = raw + target
            start = raw + (u32(data, entry) - rva)
            found.append((tuple(keys + [key]), data[start:start+u32(data, entry + 4)]))
        return found

    return walk(0, [])


def validate_tables(data):
    """Check the ordering the loader's binary search depends on.

    Returns a list of complaints; empty means every directory is well formed.
    """
    _, section = resource_section(data)
    raw, problems = section['raw'], []

    def walk(relative, depth):
        if depth > 2:
            return
        base = raw + relative
        try:
            named, ids = u16(data, base + 12), u16(data, base + 14)
            fields = [u32(data, base + 16 + i * 8) for i in range(named + ids)]
        except struct.error:
            problems.append(f'directory 0x{relative:x} runs past the .rsrc payload')
            return
        named_fields = [f for f in fields if f & 0x80000000]
        if len(named_fields) != named:
            problems.append(f'directory 0x{relative:x} named/id counts disagree with its entries')
        if named and not all(f & 0x80000000 for f in fields[:named]):
            problems.append(f'directory 0x{relative:x} does not start with its named entries')
        if any(f & 0x80000000 for f in fields[named:]):
            problems.append(f'directory 0x{relative:x} mixes named entries into the id range')
        # Only entries that really carry a string name can be compared as names;
        # a mislabelled directory is reported above rather than crashing here.
        names = [read_key(data, raw, f)[1] for f in fields[:named] if f & 0x80000000]
        if names != sorted(names, key=lambda name: name.lower()):
            problems.append(f'directory 0x{relative:x} named entries are unsorted')
        values = fields[named:]
        if values != sorted(values):
            problems.append(f'directory 0x{relative:x} id entries are unsorted')
        for i in range(named + ids):
            target = u32(data, base + 16 + i * 8 + 4)
            if target & 0x80000000:
                walk(target & 0x7FFFFFFF, depth + 1)

    walk(0, 0)
    return problems


def read_ico(path):
    """(.ico directory entries) as (width, height, colors, reserved, planes, bitcount, blob)."""
    data = Path(path).read_bytes()
    if data[:4] != b'\x00\x00\x01\x00':
        raise SystemExit(f'{path}: not an .ico file')
    count = u16(data, 4)
    if not count:
        raise SystemExit(f'{path}: empty icon directory')
    entries = []
    for i in range(count):
        at = 6 + 16 * i
        width, height, colors, reserved = data[at], data[at+1], data[at+2], data[at+3]
        planes, bitcount = struct.unpack_from('<HH', data, at + 4)
        size, start = struct.unpack_from('<II', data, at + 8)
        blob = data[start:start+size]
        if len(blob) != size:
            raise SystemExit(f'{path}: truncated icon image {i}')
        entries.append((width, height, colors, reserved, planes, bitcount, blob))
    return entries


def build_group(entries):
    """RT_GROUP_ICON payload listing icon ids 1..n."""
    group = struct.pack('<HHH', 0, 1, len(entries))
    for i, (width, height, colors, reserved, planes, bitcount, blob) in enumerate(entries):
        group += struct.pack('<BBBBHHIH', width, height, colors, reserved,
                             planes, bitcount, len(blob), i + 1)
    return group


class Directory:
    def __init__(self): self.entries = []


class Blob:
    def __init__(self, blob): self.blob = blob


def build_tree(resources):
    """Nest (keys, blob) pairs, keeping named entries first and ids ascending."""
    root, index = Directory(), {(): Directory()}
    index[()].entries = root.entries = index[()].entries
    for keys, blob in resources:
        node = root
        for depth, key in enumerate(keys[:-1]):
            path = keys[:depth+1]
            if path not in index:
                index[path] = Directory()
                node.entries.append((key, index[path]))
            node = index[path]
        node.entries.append((keys[-1], Blob(blob)))
    for node in index.values():
        node.entries.sort(key=lambda item: (1, item[0][1]) if item[0][0] == 'id'
                          else (0, item[0][1].lower()))
    return root


def serialize(root, section_rva):
    """Directory tables, then data entries, then name strings, then raw data."""
    queue, positions, cursor, i = [root], {}, 0, 0
    while i < len(queue):
        node = queue[i]
        i += 1
        positions[id(node)] = cursor
        cursor += 16 + 8 * len(node.entries)
        queue.extend(child for _, child in node.entries if isinstance(child, Directory))

    leaves = [child for node in queue for _, child in node.entries if isinstance(child, Blob)]
    data_pos = {id(leaf): cursor + 16 * n for n, leaf in enumerate(leaves)}
    cursor += 16 * len(leaves)

    name_pos = {}
    for node in queue:
        for key, _ in node.entries:
            if key[0] == 'str' and key[1] not in name_pos:
                name_pos[key[1]] = cursor
                cursor += 2 + 2 * len(key[1])
    cursor = (cursor + 3) & ~3

    blob_pos = {}
    for leaf in leaves:
        blob_pos[id(leaf)] = cursor
        cursor = (cursor + len(leaf.blob) + 3) & ~3

    out = bytearray(cursor)
    for node in queue:
        base = positions[id(node)]
        named = sum(1 for key, _ in node.entries if key[0] == 'str')
        struct.pack_into('<IIHHHH', out, base, 0, 0, 0, 0, named, len(node.entries) - named)
        for n, (key, child) in enumerate(node.entries):
            at = base + 16 + 8 * n
            field = (0x80000000 | name_pos[key[1]]) if key[0] == 'str' else key[1]
            put32(out, at + 4, (0x80000000 | positions[id(child)]) if isinstance(child, Directory)
                  else data_pos[id(child)])
            struct.pack_into('<I', out, at, field)
    for leaf in leaves:
        at = data_pos[id(leaf)]
        struct.pack_into('<IIII', out, at, section_rva + blob_pos[id(leaf)],
                         len(leaf.blob), 0, 0)
        out[blob_pos[id(leaf)]:blob_pos[id(leaf)] + len(leaf.blob)] = leaf.blob
    for name, at in name_pos.items():
        struct.pack_into('<H', out, at, len(name))
        out[at+2:at+2+2*len(name)] = name.encode('utf-16-le')
    return bytes(out)


def write_exe(path, data):
    """Write with retries: a just-exited process or a scanner can hold the file."""
    error = None
    for _ in range(40):
        try:
            Path(path).write_bytes(bytes(data))
            return
        except PermissionError as exc:
            error = exc
            time.sleep(0.25)
    raise SystemExit(f'{path}: could not write the patched exe: {error}')


def replacement_payload(data, entries):
    """Rebuild .rsrc with the .ico installed and every other resource untouched."""
    resource_dir, section = resource_section(data)
    existing = read_resources(data)
    group_keys = next((keys for keys, _ in existing if keys[0] == ('id', RT_GROUP_ICON)), None)
    if group_keys is None:
        raise SystemExit('no RT_GROUP_ICON in this executable: refusing to invent one')
    kept = [r for r in existing if r[0][0] not in (('id', RT_ICON), ('id', RT_GROUP_ICON))]
    icons = [((('id', RT_ICON), ('id', i + 1), ('id', LANG)), entry[6])
             for i, entry in enumerate(entries)]
    payload = serialize(build_tree(kept + icons + [(group_keys, build_group(entries))]),
                        section['rva'])
    if len(payload) > section['raw_size']:
        raise SystemExit(f'rebuilt .rsrc needs {len(payload)} bytes, section holds '
                         f'{section["raw_size"]}; refusing to grow the file')
    return payload, section, resource_dir, kept


def patch(exe, icon):
    entries = read_ico(icon)
    data = bytearray(Path(exe).read_bytes())
    payload, section, resource_dir, kept = replacement_payload(data, entries)
    start = section['raw']
    data[start:start+len(payload)] = payload
    data[start+len(payload):start+section['raw_size']] = b'\0' * (section['raw_size'] - len(payload))
    struct.pack_into('<I', data, section['header'] + 8, max(section['vsize'], len(payload)))
    put32(data, resource_dir, section['rva'])
    put32(data, resource_dir + 4, len(payload))
    write_exe(exe, data)
    return len(payload), len(entries), [keys for keys, _ in kept]


def check(exe, icon, data=None):
    """Verify the executable matches the .ico and kept its other resources."""
    entries = read_ico(icon)
    data = Path(exe).read_bytes() if data is None else data
    problems = validate_tables(data)
    resources = read_resources(data)
    types = {keys[0] for keys, _ in resources}
    icons = [(keys, blob) for keys, blob in resources if keys[0] == ('id', RT_ICON)]
    icons.sort(key=lambda item: item[0][1][1])
    if len(icons) != len(entries):
        problems.append(f'{len(icons)} icon images installed, .ico has {len(entries)}')
    for (keys, blob), entry in zip(icons, entries):
        if blob != entry[6]:
            problems.append(f'icon {keys[1]} differs from the .ico image {keys[1][1] - 1}')
    groups = [(keys, blob) for keys, blob in resources if keys[0] == ('id', RT_GROUP_ICON)]
    if len(groups) != 1:
        problems.append(f'{len(groups)} icon groups, expected 1')
    else:
        keys, blob = groups[0]
        count = u16(blob, 4)
        if count != len(entries):
            problems.append(f'icon group lists {count} images, .ico has {len(entries)}')
        ids = [u16(blob, 6 + 14 * i + 12) for i in range(min(count, len(entries)))]
        if ids != list(range(1, len(ids) + 1)):
            problems.append(f'icon group ids are {ids}, expected 1..{len(ids)}')
    if ('id', RT_VERSION) not in types:
        problems.append('RT_VERSION is missing')
    if ('id', RT_MANIFEST) not in types:
        problems.append('RT_MANIFEST is missing: DPI awareness and comctl32 v6 would be lost')
    return problems, len(icons), [keys for keys, _ in resources
                                  if keys[0] not in (('id', RT_ICON), ('id', RT_GROUP_ICON))]


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--exe', type=Path, help='executable to patch (default: project build)')
    parser.add_argument('--icon', type=Path, default=DEFAULT_ICON, help='source .ico')
    parser.add_argument('--check', action='store_true', help='verify without writing')
    args = parser.parse_args()

    exe = args.exe or next((p for p in CANDIDATE_EXES if p.exists()), None)
    if exe is None or not exe.exists():
        parser.error('no executable found; pass --exe PATH')
    if not args.icon.exists():
        parser.error(f'icon not found: {args.icon}')

    if args.check:
        problems, count, kept = check(exe, args.icon)
        print(f'{exe.name}: {count} icon images', 'match' if not problems else 'DO NOT match',
              args.icon.name)
        print('  kept resources:', ', '.join('/'.join(f'{k[0]}:{k[1]}' for k in keys)
                                             for keys in kept) or '(none)')
        for problem in problems:
            print(f'  FAIL {problem}')
        if problems:
            return 1
        print('PASS')
        return 0

    payload, count, kept = patch(exe, args.icon)
    print(f'{exe.name}: .rsrc payload {payload} bytes, {count} icon images from {args.icon.name}')
    print('  kept resources:', ', '.join('/'.join(f'{k[0]}:{k[1]}' for k in keys)
                                         for keys in kept) or '(none)')
    print('  Explorer may keep drawing a cached icon until its view is refreshed.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
