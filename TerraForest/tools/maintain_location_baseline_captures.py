# SPDX-License-Identifier: 0BSD
"""Cold-retain receipt-proven historical bulk fixtures; never touch player saves."""
import argparse
import hashlib
import json
import re
from pathlib import Path

from development_storage import ROOT, LIMITS, usage
from maintain_performance_artifacts import no_game_processes, owned_lease
from retained_artifacts import Store, archive, confined, digest, retire, verify
from resource_limits import require_free_space


def candidates(root=ROOT,keep_ready=2):
    if keep_ready not in (1,2):raise ValueError('Keep one or two ready bulk fixtures')
    root=Path(root).resolve();base=root/'reports/location_baseline';ready=[]
    for receipt in sorted(base.glob('*/run.json')):
        folder=confined(receipt.parent,base);record=json.loads(receipt.read_text())
        if not record.get('passed') or any((folder/n).exists() for n in ('.retain','RETAIN_READY','bulk.archive.json')):
            continue
        revision=record.get('revision','')
        if not re.fullmatch('[0-9a-f]{40}',revision):continue
        members=[];proofs=[]
        for row in record.get('runs',[]):
            if row.get('phase')!='create' or row.get('variant') not in ('debug','release','pack'):continue
            if row.get('result',{}).get('exit_code')!=0 or not row['result'].get('passed'):continue
            project=folder/row['variant'];driver=project/'create/location_baseline.gd'
            command=row.get('command',[])
            if '--baseline-dir='+str(project) not in command or '--script' not in command:continue
            if command[command.index('--script')+1]!=str(driver):continue
            if not any(r.get('variant')==row['variant'] and r.get('phase')=='reopen' and
                       r.get('result',{}).get('exit_code')==0 and r['result'].get('passed') for r in record['runs']):continue
            # Undo exactly the launcher's substitutions and match the source hash
            # recorded before execution. This includes then-uncommitted drivers;
            # their filename alone never grants ownership.
            frozen=confined(driver,folder).read_text()
            original=frozen.replace((project/'create').as_posix()+'/user/','user://').replace((project/'create').as_posix()+'/reports','res://reports')
            normalized_hashes={hashlib.sha256(value.encode()).hexdigest() for value in (original,original.replace('\n','\r\n'))}
            if row.get('source_sha256') not in normalized_hashes:continue
            bulk=project/'bulk'
            if not bulk.is_dir():continue
            for path in bulk.glob('*.baseline'):
                confined(path,folder)
                if (not re.fullmatch(r'[0-9a-f]{64}\.baseline',path.name) or
                        not 15*2**20<=path.stat().st_size<16*2**20 or
                        path.stat().st_mtime_ns>receipt.stat().st_mtime_ns+2_000_000_000):continue
                members.append(path.relative_to(folder).as_posix())
            proofs.append(dict(path=str(driver),sha256=digest(driver)))
        if members:ready.append((folder,members,dict(kind='completed-location-bulk-fixtures',run_sha256=digest(receipt),drivers=proofs)))
    return ready[:-keep_ready]


def maintain(apply=False,root=ROOT,keep_ready=2):
    root=Path(root).resolve();selected=candidates(root,keep_ready)
    amount=sum((folder/name).stat().st_size for folder,members,_ in selected for name in members)
    result=dict(keep_ready=keep_ready,runs=len(selected),planned_bytes=amount,retired_bytes=0,manifests=[])
    if not apply or not selected:return result
    no_game_processes()
    with owned_lease(root/'reports/retained_artifacts/writer',root):
        current=usage(root)
        # Recovery adds no loose report bytes until more bytes have been retired.
        # Stage all new manifests in the archive category, whose limit still
        # applies. This cannot admit a new capture above the normal report cap.
        allowance=1024*1024
        if current['archive']+amount+allowance>LIMITS['archive']:
            raise OSError('Archive headroom insufficient; original fixtures retained')
        require_free_space(root,amount+allowance)
        store=Store(root/'reports/retained_artifacts/chunks')
        store.budget=LIMITS['archive']-(current['archive']-store.bytes)-allowance
        staged=root/'reports/retained_artifacts/location_bulk_recovery'
        for folder,members,proof in selected:
            no_game_processes()
            if any((folder/n).exists() for n in ('.retain','RETAIN_READY')):continue
            if digest(folder/'run.json')!=proof['run_sha256']:raise ValueError('Ownership receipt changed')
            if any(digest(Path(p['path']))!=p['sha256'] for p in proof['drivers']):raise ValueError('Frozen driver changed')
            pending=staged/(folder.name+'.json')
            saved=archive(folder,members,pending,store,proof)
            verify(saved,store)
            removed=retire(saved,store,folder)
            if pending.stat().st_size>removed:raise ValueError('Recovery must shrink loose reports')
            destination=folder/'bulk.archive.json'
            pending.replace(destination)
            result['retired_bytes']+=removed;result['manifests'].append(str(destination))
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--apply',action='store_true')
    parser.add_argument('--keep-ready',type=int,choices=(1,2),default=2)
    args=parser.parse_args()
    print(json.dumps(maintain(args.apply,keep_ready=args.keep_ready),indent=2))
