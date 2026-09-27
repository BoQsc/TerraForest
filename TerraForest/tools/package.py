"""Create deterministic source/addon archives with a final content hash manifest."""
from pathlib import Path
import hashlib
import json
import zipfile

root=Path(__file__).resolve().parents[1]
destination=root/'dist'
destination.mkdir(exist_ok=True)
excluded={'.godot','.build','.git','dist','reports','__pycache__'}
files=sorted(p for p in root.rglob('*') if p.is_file() and not any(part in excluded for part in p.relative_to(root).parts) and p.name!='MANIFEST.sha256.json')
manifest={p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
manifest_path=root/'MANIFEST.sha256.json'
manifest_path.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
files.append(manifest_path)

def archive(path,entries):
    with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as output:
        for file in sorted(entries):
            info=zipfile.ZipInfo(file.relative_to(root).as_posix(),date_time=(2026,9,27,0,0,0))
            info.compress_type=zipfile.ZIP_DEFLATED
            info.external_attr=0o644<<16
            output.writestr(info,file.read_bytes())
    with zipfile.ZipFile(path) as test:
        if test.testzip() is not None:
            raise RuntimeError('Archive CRC verification failed')
    print(f'{path.name}: {path.stat().st_size:,} bytes; SHA256 {hashlib.sha256(path.read_bytes()).hexdigest()}')

archive(destination/'TerraForest-source.zip',files)
for addon in ['volumetric_terrain','vegetation','world_ecosystem','world_runtime','presentation','volumetric_water']:
    archive(destination/(addon+'.zip'),[p for p in files if p.relative_to(root).as_posix().startswith('addons/'+addon+'/')])
