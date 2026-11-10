# SPDX-License-Identifier: 0BSD
"""Retire exact obsolete output bytes only after complete GitHub verification."""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import os
import stat

from generated_backup import GitHub, read_json, source_path, write_json
from retained_artifacts import confined, digest, identity
from maintain_performance_artifacts import no_game_processes, owned_lease

ROOT = Path(__file__).resolve().parents[1]
MEDIA = {'.png','.jpg','.jpeg','.gif','.webp','.mp4'}
BINARY = {'.pck','.dll','.pdb'}
TRACE = re.compile(r'(?:frames|measurements|trace_[0-9]+)\.json\Z')


def referenced_media(root):
    git_root = Path(subprocess.check_output(['git','rev-parse','--show-toplevel'],cwd=root,text=True).strip())
    paths = subprocess.check_output(['git','ls-files','-z','*.md','*.gd','*.tscn','*.tres'],cwd=git_root).decode().split('\0')
    result = set()
    for name in filter(None,paths):
        path = git_root/name
        if not path.is_file():continue
        content = path.read_text(encoding='utf-8',errors='replace').replace('\\','/')
        for match in re.finditer(r'reports/[^\s\)\]<>"\x27`]+\.(?:png|jpg|jpeg|gif|webp|mp4)',content):
            result.add('project/'+match.group())
    return result


def candidates(record, root, referenced=(), keep=2):
    recent = set()
    families = {}
    for row in record['files']:
        parts = Path(row['path']).parts
        if row['path'].startswith('project/reports/') and len(parts)>4 and parts[-1]=='run.json':
            families.setdefault(parts[2],[]).append((row['mtime_ns'],'/'.join(parts[:-1])+'/'))
    for runs in families.values():
        recent.update(prefix for _,prefix in sorted(runs,reverse=True)[:keep])
    selected, skipped = [], []
    for row in record['files']:
        name = row['path']
        if not name.startswith(('project/reports/','project/build/')):continue
        if name.startswith(('project/reports/retained_artifacts/','project/reports/artifact_retention/')):continue
        filename=Path(name)
        if filename.suffix.lower() not in MEDIA|BINARY and not TRACE.fullmatch(filename.name):continue
        if name in referenced or any(name.startswith(prefix) for prefix in recent):continue
        path=source_path(record,row)
        if not path.exists():continue
        allowed=root/('reports' if name.startswith('project/reports/') else '.build')
        confined(path,allowed)
        if any((parent/'.retain').exists() or (parent/'RETAIN_READY').exists() for parent in [path.parent,*path.parents] if parent.is_relative_to(allowed)):
            skipped.append(dict(path=name,reason='explicit pin'));continue
        selected.append(row)
    return selected,skipped


def retire_outputs(catalog_path, receipt_path, root=ROOT, apply=False):
    root=Path(root).absolute()
    record,remote=read_json(catalog_path),read_json(receipt_path)
    if remote.get('complete') is not True or remote.get('catalog_sha256') != digest(catalog_path):
        raise ValueError('Complete matching backup verification is required')
    if remote.get('repository')!='BoQsc/TerraForest' or remote.get('branch')!='codex/generated-backup-2026-11-10':
        raise ValueError('Unexpected backup destination')
    covered={key for a in remote['assets'] for key in a['objects']}
    selected,skipped=candidates(record,root,referenced_media(root))
    if any(row['sha256'] not in covered for row in selected):raise ValueError('Backup omits a selected object')
    result=dict(schema=1,apply=apply,repository=remote['repository'],branch=remote['branch'],tag=remote['tag'],
                catalog_sha256=digest(catalog_path),planned_files=len(selected),planned_bytes=sum(r['bytes'] for r in selected),
                retained=skipped,removed=[],errors=[])
    folder=root/'reports/artifact_retention';folder.mkdir(parents=True,exist_ok=True)
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    receipt=folder/('cold_outputs_'+stamp+'.json')
    result['receipt']=str(receipt)
    if not apply:
        result['selected']=[r['path'] for r in selected]
        write_json(receipt,result)
        return result
    no_game_processes()
    with owned_lease(folder/'cold_writer',root):
        api=GitHub(remote['repository'])
        api.verify_receipt(remote)
        checked=[]
        # Validate the complete batch before removing any source file.
        for row in selected:
            path=source_path(record,row);before=identity(path)
            if before[2]!=row['bytes'] or digest(path)!=row['sha256'] or identity(path)!=before:
                raise ValueError('Changed output retained: '+str(path))
            checked.append((row,path,before))
        print('Verified cold-output batch',len(checked),'files',round(result['planned_bytes']/2**30,3),'GiB',flush=True)
        write_json(receipt,result)
        try:
            for row,path,before in checked:
                confined(path,root)
                if identity(path)!=before:raise ValueError('Output changed before retirement')
                marker=path.parent/'.cold-archive-20261110.json'
                previous=read_json(marker) if marker.exists() else dict(catalog_sha256=result['catalog_sha256'],repository=remote['repository'],tag=remote['tag'],files={})
                if previous['catalog_sha256']!=result['catalog_sha256']:raise ValueError('Cold archive ownership differs')
                previous['files'][path.name]=dict(path=row['path'],sha256=row['sha256'],bytes=row['bytes'])
                write_json(marker,previous)
                # Old captured media may carry Windows' read-only attribute.
                # Clear it only for the exact byte-verified backed-up candidate.
                mode = path.stat().st_mode
                readonly = os.name == 'nt' and bool(path.stat().st_file_attributes & 1)
                if readonly:path.chmod(stat.S_IWRITE)
                try:
                    path.unlink()  # Exact fully verified file; no recursive deletion.
                except PermissionError as error:
                    if readonly and path.exists():path.chmod(mode)
                    result['retained'].append(dict(path=row['path'],reason='Operating system refused removal',error=str(error)))
                    continue
                except OSError:
                    if readonly and path.exists():path.chmod(mode)
                    raise
                result['removed'].append(dict(path=row['path'],bytes=row['bytes'],sha256=row['sha256']))
                if len(result['removed'])%100==0:write_json(receipt,result)
        except (OSError,ValueError) as error:
            result['errors'].append(str(error))
        finally:
            write_json(receipt,result)
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('catalog',type=Path);parser.add_argument('receipt',type=Path);parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    result=retire_outputs(args.catalog,args.receipt,apply=args.apply)
    print(json.dumps({k:v for k,v in result.items() if k not in ('removed','selected','retained')},indent=2))
    print('Removed GiB',sum(r['bytes'] for r in result['removed'])/2**30)
    raise SystemExit(int(bool(result['errors'])))
