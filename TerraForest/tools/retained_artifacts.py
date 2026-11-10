# SPDX-License-Identifier: 0BSD
"""Lossless, verified development archives. Never evict regression evidence."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import uuid
import zlib

from resource_limits import require_free_space

CHUNK_BYTES = 1024 * 1024
ARCHIVE_BUDGET = 10 * 1024**3
CAPTURE_BUDGET = 8 * 1024**3
HEX = re.compile(r'[0-9a-f]{64}\Z')


def ordinary(path):
    info = Path(path).lstat()
    if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 0x400:
        raise ValueError('Linked path retained: ' + str(path))
    if not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)):
        raise ValueError('Special file retained: ' + str(path))
    return info


def confined(path, root):
    path, root = Path(path).absolute(), Path(root).absolute()
    path.relative_to(root)
    for parent in [path, *path.parents]:
        ordinary(parent)
        if parent == root:
            break
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError('Path escapes root: ' + str(path))
    return path


def ordinary_ancestors(path):
    for parent in [Path(path).absolute(), *Path(path).absolute().parents]:
        if parent.exists():
            ordinary(parent)


def relative_name(name):
    value = PurePosixPath(name)
    if not name or value.is_absolute() or any(p in ('', '.', '..') or ':' in p or '\\' in p for p in name.split('/')):
        raise ValueError('Unsafe archive member: ' + name)
    return value


def tree_bytes(root):
    root = Path(root)
    if not root.exists():
        return 0
    ordinary(root)
    total = 0
    for folder, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            info = ordinary(Path(folder) / name)
            if stat.S_ISREG(info.st_mode):
                total += info.st_size
    return total


def digest(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def identity(path):
    info = ordinary(path)
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns


class Store:
    def __init__(self, path, budget=ARCHIVE_BUDGET):
        self.path = Path(path).absolute()
        ordinary_ancestors(self.path)
        self.budget = budget
        self.bytes = tree_bytes(self.path)
        self.verified = set()

    def get(self, key):
        if not isinstance(key, str) or not HEX.fullmatch(key):
            raise ValueError('Invalid chunk identity')
        path = confined(self.path / key[:2] / (key + '.z'), self.path)
        if path.stat().st_size > CHUNK_BYTES + 65536:
            raise ValueError('Oversized archived chunk: ' + key)
        decoder = zlib.decompressobj()
        try:
            data = decoder.decompress(path.read_bytes(), CHUNK_BYTES + 1)
        except zlib.error as error:
            raise ValueError('Corrupt archived chunk: ' + key) from error
        if len(data) > CHUNK_BYTES or not decoder.eof or decoder.unused_data or hashlib.sha256(data).hexdigest() != key:
            raise ValueError('Corrupt archived chunk: ' + key)
        return data

    def put(self, data):
        key = hashlib.sha256(data).hexdigest()
        path = self.path / key[:2] / (key + '.z')
        if path.exists():
            if key not in self.verified:
                self.get(key)
                self.verified.add(key)
            return key
        payload = zlib.compress(data, 6)
        if self.bytes + len(payload) > self.budget:
            raise OSError('Retained archive budget reached; evidence preserved, further archival refused')
        existing = self.path
        while not existing.exists():
            existing = existing.parent
        require_free_space(existing, len(payload))
        ordinary(existing)
        path.parent.mkdir(parents=True, exist_ok=True)
        confined(path.parent, self.path)
        temporary = path.with_name(key + '.' + uuid.uuid4().hex + '.tmp')
        with temporary.open('xb') as output:
            output.write(payload)
            output.flush()
            os.fsync(output.fileno())
        temporary.rename(path)
        self.bytes += len(payload)
        self.get(key)
        self.verified.add(key)
        return key


def load_manifest(path):
    ordinary(path)
    record = json.loads(Path(path).read_text(encoding='utf-8'))
    if record.get('schema') != 1 or record.get('chunk_bytes') != CHUNK_BYTES:
        raise ValueError('Unsupported retained archive')
    seen = set()
    for row in record['files']:
        relative_name(row['path'])
        key = row['path'].casefold() if os.name == 'nt' else row['path']
        if key in seen or not HEX.fullmatch(row['sha256']) or type(row['bytes']) is not int or row['bytes'] < 0:
            raise ValueError('Invalid retained file record')
        seen.add(key)
    for name in record['directories']:
        relative_name(name)
    return record


def verify(record, store):
    total = 0
    for row in record['files']:
        checksum = hashlib.sha256()
        size = 0
        for chunk in row['chunks']:
            data = store.get(chunk)
            checksum.update(data)
            size += len(data)
        if size != row['bytes'] or checksum.hexdigest() != row['sha256']:
            raise ValueError('Archived file differs: ' + row['path'])
        total += size
    return total


def archive(root, members, manifest, store, provenance):
    root, manifest = Path(root).absolute(), Path(manifest).absolute()
    ordinary_ancestors(root)
    ordinary_ancestors(manifest)
    ordinary(root)
    if manifest.exists():
        record = load_manifest(manifest)
        if record['source_root'] != str(root) or record['provenance'] != provenance:
            raise ValueError('Archive ownership differs')
        verify(record, store)
        return record
    files, directories = set(), set()
    for member in members:
        path = confined(root / relative_name(member), root)
        if path.is_file():
            files.add(path)
        else:
            directories.add(path)
            for folder, dirs, names in os.walk(path, followlinks=False):
                for name in dirs:
                    directories.add(confined(Path(folder) / name, root))
                for name in names:
                    files.add(confined(Path(folder) / name, root))
    record = dict(schema=1, chunk_bytes=CHUNK_BYTES, source_root=str(root), provenance=provenance,
                  directories=sorted(p.relative_to(root).as_posix() for p in directories), files=[])
    for path in sorted(files):
        before = identity(path)
        checksum, chunks = hashlib.sha256(), []
        with path.open('rb') as source:
            while data := source.read(CHUNK_BYTES):
                checksum.update(data)
                chunks.append(store.put(data))
        if identity(path) != before:
            raise ValueError('Source changed while archiving: ' + str(path))
        record['files'].append(dict(path=path.relative_to(root).as_posix(), bytes=before[2],
                                   sha256=checksum.hexdigest(), chunks=chunks))
    verify(record, store)
    # Publish only after a complete reconstruction/hash check. No source removed yet.
    manifest.parent.mkdir(parents=True, exist_ok=True)
    temporary = manifest.with_name(manifest.name + '.' + uuid.uuid4().hex + '.tmp')
    with temporary.open('x', encoding='utf-8') as output:
        json.dump(record, output, indent=2)
        output.flush()
        os.fsync(output.fileno())
    temporary.rename(manifest)
    return record


def retire(record, store, allowed_root, keep=()):
    root = Path(allowed_root).absolute()
    ordinary_ancestors(root)
    if record['source_root'] != str(root):
        raise ValueError('Retirement root does not match archive')
    ordinary(root)
    verify(record, store)
    selected = []
    for row in record['files']:
        if row['path'] in keep:
            continue
        path = root / relative_name(row['path'])
        if not path.exists():
            continue  # Resumable retirement after a verified archive was published.
        confined(path, root)
        before = identity(path)
        if before[2] != row['bytes'] or digest(path) != row['sha256'] or identity(path) != before:
            raise ValueError('Changed source retained: ' + str(path))
        selected.append((path, before))
    # All sources checked before deleting any. Only exact verified file paths.
    amount = 0
    for path, before in selected:
        confined(path, root)
        if identity(path) != before:
            raise ValueError('Source identity changed before removal: ' + str(path))
        path.unlink()
        amount += before[2]
    for name in sorted(record['directories'], key=lambda n: len(n.split('/')), reverse=True):
        path = root / relative_name(name)
        if path.exists():
            confined(path, root)
            if not any(path.iterdir()):
                path.rmdir()
    return amount


def restore(manifest, store, destination):
    record = load_manifest(manifest)
    destination = Path(destination).absolute()
    ordinary_ancestors(destination)
    if destination.exists():
        raise FileExistsError('Restore requires a new directory; existing saves are never overwritten')
    parent = destination.parent
    while not parent.exists():
        parent = parent.parent
    ordinary(parent)
    require_free_space(parent, sum(r['bytes'] for r in record['files']))
    verify(record, store)
    destination.mkdir(parents=True)
    for name in record['directories']:
        (destination / relative_name(name)).mkdir(parents=True, exist_ok=True)
    for row in record['files']:
        path = destination / relative_name(row['path'])
        path.parent.mkdir(parents=True, exist_ok=True)
        confined(path.parent, destination)
        with path.open('xb') as output:
            for chunk in row['chunks']:
                output.write(store.get(chunk))
        if digest(path) != row['sha256']:
            raise ValueError('Restored file failed verification')
    return dict(files=len(record['files']), bytes=sum(r['bytes'] for r in record['files']))
