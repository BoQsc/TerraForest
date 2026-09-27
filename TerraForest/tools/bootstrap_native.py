"""Install pinned Zig and prebuilt godot-cpp into a user-local cache; never builds bindings."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import urllib.request
import zipfile

ROOT=Path(__file__).resolve().parents[1]
LOCK=json.loads((ROOT/'native_toolchain.lock.json').read_text(encoding='utf-8'))
CACHE=Path(os.environ.get('TERRAFOREST_TOOLCHAINS',str(Path(os.environ.get('LOCALAPPDATA',Path.home()))/'TerraForest/toolchains'))).resolve()

def digest(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file,'sha256').hexdigest()

def install(name):
    spec=LOCK[name]
    folder=CACHE/(name+'-'+spec['sha256'][:16])
    marker=folder/'.verified.json'
    if marker.exists() and json.loads(marker.read_text()).get('sha256')==spec['sha256']:
        print(f'Reusing verified {name}: {folder}',flush=True)
        return folder
    archives=CACHE/'archives'
    archives.mkdir(parents=True,exist_ok=True)
    archive=archives/(spec['sha256']+'.zip')
    if not archive.exists() or digest(archive)!=spec['sha256']:
        pending=archive.with_suffix('.part')
        print(f'Downloading {name} ({spec["size"]:,} bytes)',flush=True)
        request=urllib.request.Request(spec['url'],headers={'User-Agent':'TerraForest-native-bootstrap'})
        with urllib.request.urlopen(request,timeout=60) as response,pending.open('wb') as output:
            shutil.copyfileobj(response,output,1024*1024)
        if pending.stat().st_size!=spec['size'] or digest(pending)!=spec['sha256']:
            raise RuntimeError(f'{name} download size/SHA-256 mismatch; nothing executed or extracted')
        pending.replace(archive)
    folder.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(archive) as package:
        for item in package.infolist():
            target=(folder/item.filename).resolve()
            if target!=folder and folder not in target.parents:
                raise ValueError('Archive path escapes toolchain cache: '+item.filename)
        package.extractall(folder)
    marker.write_text(json.dumps(spec,indent=2),encoding='utf-8')
    print(f'Installed verified {name}: {folder}',flush=True)
    return folder

def bootstrap():
    CACHE.mkdir(parents=True,exist_ok=True)
    existing=os.environ.get('ZIG_EXECUTABLE') or shutil.which('zig')
    if existing:
        version=subprocess.check_output([existing,'version'],text=True).strip()
        if version!=LOCK['zig']['version']:
            print(f'Existing Zig {version} differs from pinned ABI toolchain; installing matching version',flush=True)
            existing=None
    names=['godot_cpp'] if existing else ['zig','godot_cpp']
    with ThreadPoolExecutor(len(names)) as pool:
        installed=dict(zip(names,pool.map(install,names)))
    zig=Path(existing) if existing else next(installed['zig'].rglob('zig.exe'))
    version=subprocess.check_output([str(zig),'version'],text=True).strip()
    if version!=LOCK['zig']['version']:
        raise RuntimeError('Unexpected Zig version: '+version)
    cpp=installed['godot_cpp']
    info={'zig':str(zig),'zig_version':version,'godot_cpp':str(cpp),'lock_sha256':digest(ROOT/'native_toolchain.lock.json')}
    build=ROOT/'.build'
    build.mkdir(exist_ok=True)
    (build/'native_toolchain.json').write_text(json.dumps(info,indent=2),encoding='utf-8')
    print(json.dumps(info,indent=2),flush=True)
    return info

if __name__=='__main__':
    bootstrap()
