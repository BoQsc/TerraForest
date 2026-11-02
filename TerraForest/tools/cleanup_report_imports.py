# SPDX-License-Identifier: 0BSD
"""Remove only regenerable imports mapped to retained report images; dry run by default."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import stat

ROOT = Path(__file__).resolve().parents[1]


def ordinary(path, directory=False):
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 0x400:
        raise ValueError('Linked path retained: ' + str(path))
    if directory != stat.S_ISDIR(info.st_mode):
        raise ValueError('Unexpected path type: ' + str(path))
    return info


def identity(path):
    info = ordinary(path)
    return [info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns]


def candidates(root):
    root = root.absolute()
    reports = root / 'reports'
    imports = root / '.godot/imported'
    for path in (root, reports, root / '.godot', imports):
        ordinary(path, True)
    ordinary(reports / '.gdignore')
    found = {}
    for folder, directories, files in os.walk(reports, followlinks=False):
        for name in directories:
            ordinary(Path(folder) / name, True)
        for name in files:
            if not name.endswith('.import'):
                continue
            mapping = Path(folder) / name
            ordinary(mapping)
            source = mapping.with_suffix('')
            if source.suffix.lower() not in ('.png', '.jpg', '.jpeg', '.webp') or not source.is_file():
                continue
            ordinary(source)
            contents = mapping.read_text(encoding='utf-8')
            declared = re.search(r'^source_file="([^"]+)"$', contents, re.M)
            expected = 'res://' + source.relative_to(root).as_posix()
            if not declared or declared.group(1) != expected:
                continue
            mapped = set(re.findall(r'"res://(\.godot/imported/[^"\r\n]+\.ctex)"', contents))
            for relative in mapped:
                target = root / relative
                if target.parent != imports or not target.is_file():
                    continue
                if not re.fullmatch(re.escape(source.name) + r'-[0-9a-f]{32}\.ctex', target.name):
                    continue
                for artifact in (target, target.with_suffix('.md5')):
                    if artifact.is_file():
                        found[str(artifact)] = dict(path=str(artifact), identity=identity(artifact),
                            mapping=str(mapping), mapping_sha256=hashlib.sha256(mapping.read_bytes()).hexdigest(),
                            source=str(source), source_identity=identity(source))
    return list(found.values())


def remove(candidate, root):
    target = Path(candidate['path'])
    imports = root.absolute() / '.godot/imported'
    for directory in (root.absolute(), imports.parent, imports):
        ordinary(directory, True)
    if target.parent != imports or target.resolve().parent != imports.resolve():
        raise ValueError('Import target escapes verified directory')
    mapping = Path(candidate['mapping'])
    source = Path(candidate['source'])
    if identity(target) != candidate['identity'] or identity(source) != candidate['source_identity']:
        raise ValueError('Source or imported data changed during cleanup')
    ordinary(mapping)
    if hashlib.sha256(mapping.read_bytes()).hexdigest() != candidate['mapping_sha256']:
        raise ValueError('Import mapping changed during cleanup')
    target.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    if args.apply and not args.offline:
        parser.error('Close Godot and use --offline before removing its imports')
    selected = candidates(ROOT)
    print(f'{len(selected)} redundant report imports: {sum(row["identity"][2] for row in selected) / 2**30:.2f} GiB', flush=True)
    if not args.apply:
        return
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    receipt = ROOT / 'reports' / ('report_import_cleanup_' + stamp + '.json')
    record = dict(scope='Only mapped report-image imports; original images and mappings retained',
                  candidates=selected, removed=[], errors=[])
    receipt.write_text(json.dumps(record, indent=2), encoding='utf-8')
    try:
        for candidate in selected:
            try:
                remove(candidate, ROOT)
                record['removed'].append(candidate['path'])
            except (OSError, ValueError) as error:
                record['errors'].append(str(error))
    finally:
        receipt.write_text(json.dumps(record, indent=2), encoding='utf-8')
    print(f'Removed {len(record["removed"])} regenerable files; errors={len(record["errors"])}; receipt={receipt}')


if __name__ == '__main__':
    main()
