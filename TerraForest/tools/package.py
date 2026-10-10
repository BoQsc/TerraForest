"""Create deterministic source archives and declared addon dependency bundles."""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {'.godot', '.build', '.git', 'dist', 'reports', '__pycache__'}
# These are distribution dependencies, including optional native acceleration.
# They do not claim that a scene adapter works without a host-world contract.
DEPENDENCIES = {
    'player_runtime': [], 'presentation': [], 'world_runtime': [],
    'vegetation_runtime': [], 'volumetric_water': [],
    'volumetric_terrain': ['world_runtime', 'volumetric_water'],
    'structures': ['volumetric_terrain'],
    'vegetation': ['vegetation_runtime'],
    'world_ecosystem': ['vegetation', 'volumetric_terrain', 'vegetation_runtime'],
    'vehicle_runtime': [],
}
ASSETS = {'vehicle_runtime': ['vehicle_demo']}

def include_file(path, root=ROOT):
    return (path.is_file() and not any(part in EXCLUDED for part in path.relative_to(root).parts)
            and path.name != 'MANIFEST.sha256.json'
            and not (path.name.startswith('~') and path.suffix.lower() == '.dll'))

def dependency_closure(addon):
    result = set()
    def visit(name):
        if name in result:
            return
        if name not in DEPENDENCIES:
            raise ValueError('Undeclared addon: ' + name)
        result.add(name)
        for dependency in DEPENDENCIES[name]:
            visit(dependency)
    visit(addon)
    return sorted(result)

def addon_entries(addon, root=ROOT):
    names = dependency_closure(addon)
    directories = ['addons/' + name for name in names]
    for name in names:
        directories.extend(ASSETS.get(name, []))
    files = {root/'LICENSE.txt'}
    for directory in directories:
        folder = root/directory
        if not folder.is_dir():
            raise ValueError('Missing package directory: ' + directory)
        files.update(p for p in folder.rglob('*') if include_file(p, root))
    if not all(p.is_file() for p in files):
        raise ValueError('Missing required license or package file')
    metadata = {'requested_addon': addon, 'included_addons': names,
                'asset_directories': [d for d in directories if not d.startswith('addons/')],
                'binary_support': 'Godot 4.7 Windows x86-64 single precision',
                'qualification': 'Dependency bundle; host scene contracts and clean runtime qualification remain addon-specific.'}
    return sorted(files), metadata

def archive(path, entries, root=ROOT, metadata=None):
    content = {p.relative_to(root).as_posix(): p.read_bytes() for p in entries}
    if metadata is not None:
        content['ADDON_PACKAGE.json'] = (json.dumps(metadata, indent=2)+'\n').encode('utf-8')
    manifest = {name: hashlib.sha256(data).hexdigest() for name, data in sorted(content.items())}
    content['MANIFEST.sha256.json'] = (json.dumps(manifest, indent=2)+'\n').encode('utf-8')
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as output:
        for name, data in sorted(content.items()):
            info = zipfile.ZipInfo(name, date_time=(2026,9,27,0,0,0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            output.writestr(info, data)
    with zipfile.ZipFile(path) as check:
        if check.testzip() is not None:
            raise RuntimeError('Archive CRC verification failed')
        for name, digest in manifest.items():
            if hashlib.sha256(check.read(name)).hexdigest() != digest:
                raise RuntimeError('Archive hash verification failed: ' + name)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    print(f'{path.name}: {path.stat().st_size:,} bytes; SHA256 {digest}')
    return digest

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--addon', choices=sorted(DEPENDENCIES), help='Only build this dependency bundle')
    args = parser.parse_args()
    if not args.addon:
        files = sorted(p for p in ROOT.rglob('*') if include_file(p))
        archive(ROOT/'dist/TerraForest-source.zip', files)
    for addon in [args.addon] if args.addon else sorted(DEPENDENCIES):
        entries, metadata = addon_entries(addon)
        archive(ROOT/'dist'/(addon+'.zip'), entries, metadata=metadata)

if __name__ == '__main__':
    main()
