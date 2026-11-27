# SPDX-License-Identifier: 0BSD
"""Run the controlled vegetation matrix without changing production settings."""
import argparse
import json
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / 'tests/fixtures/vegetation_lab.json'


def configurations(plan):
    result = {}
    for case in plan['cases']:
        parent, changes = case['parent'], case['change']
        if case['id'] in result or (parent is not None and parent not in result):
            raise ValueError('Matrix needs unique cases and an earlier parent')
        if (parent is None and changes) or (parent is not None and len(changes) != 1):
            raise ValueError('Each intervention must change exactly one declared factor')
        if not changes.keys() <= plan['baseline'].keys():
            raise ValueError('Unknown experiment factor')
        value = dict(plan['baseline'] if parent is None else result[parent])
        if parent is not None and all(value[k] == v for k, v in changes.items()):
            raise ValueError('Intervention must actually change its factor')
        value.update(changes)
        result[case['id']] = value
    return result


def active_render_jobs(exclude_run_id=None):
    # Query only process names/commands; never stop a player session or another job.
    command = "Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'godot|TerraForest' -and ($_.CommandLine -match '--script|--path|--main-pack' -or $_.Name -eq 'TerraForest.exe') } | Select-Object ProcessId,Name,@{Name='headless';Expression={$_.CommandLine -match '--headless'}} | ConvertTo-Json -Compress"
    if exclude_run_id:
        if len(exclude_run_id)!=32 or any(c not in '0123456789abcdef' for c in exclude_run_id):
            raise ValueError('Invalid owned run identity')
        command=command.replace('} | Select-Object',"-and $_.CommandLine -notlike '*--lab-run-id="+exclude_run_id+"*' } | Select-Object")
    data = subprocess.check_output(['powershell', '-NoProfile', '-Command', command], text=True).strip()
    return json.loads(data) if data else []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--slot', default='Homestead_Valley')
    parser.add_argument('--cases', help='Comma-separated interventions; parents are included automatically')
    parser.add_argument('--list', action='store_true', help='Validate and print the matrix; no engine/output allocation')
    parser.add_argument('--gameplay', action='store_true', help='Run the physical gameplay gate with the same admission/overlap checks')
    parser.add_argument('--grounded-view',action='store_true',help='Lab camera at a natural grass root plus normal eye height')
    parser.add_argument('--paired-cost',nargs='?',const='grass',choices=('grass','fern','fern_surface','fern_cluster','fern_vertex','fern_trim','complete','details','detail_clustered','detail_lookup','details_split','detail_early','detail_runtime'),help='Interleave matched candidate costs in repeated ABBA order')
    parser.add_argument('--source-cost',action='store_true',help='Measure lab cost at the source frame cap and VSync instead of uncapped headroom')
    parser.add_argument('--cost-only',action='store_true',help='Paired cost plus framing/reference/near invariants; skip already-tested intervention image replays')
    parser.add_argument('--wait-idle',action='store_true',help='Prepare the paired lab, then disable its viewport until monitored GPU test jobs are idle')
    parser.add_argument('--visual-only',action='store_true',help='Deterministic image experiment only; record other jobs, skip all cost windows')
    control=parser.add_mutually_exclusive_group()
    control.add_argument('--opaque-control', action='store_true')
    control.add_argument('--previous-filter-control', action='store_true')
    control.add_argument('--fern-trial',action='store_true',help='Apply the unpromoted fern experiment in memory during physical gameplay')
    control.add_argument('--fern-cluster-trial',action='store_true',help='Apply the unpromoted seven-frond experiment in memory during physical gameplay')
    args = parser.parse_args()
    if not (args.cases or args.list or args.gameplay or args.paired_cost):
        parser.error('Select a bounded --cases batch, --paired-cost, or --gameplay; the combined matrix exceeds the measured resource budget')
    if (args.opaque_control or args.previous_filter_control or args.fern_trial or args.fern_cluster_trial) and not args.gameplay:
        parser.error('Gameplay controls require --gameplay')
    if args.gameplay and (args.cases or args.list):parser.error('Gameplay and matrix selection are separate gates')
    if args.gameplay and args.grounded_view:parser.error('Physical gameplay already uses its normal eye height')
    if args.paired_cost and (args.gameplay or args.cases):parser.error('Paired cost selects its matched candidate cases automatically')
    if args.visual_only and (args.gameplay or args.paired_cost):parser.error('Visual-only applies to matrix image experiments')
    if args.source_cost and (args.visual_only or args.gameplay):parser.error('Source cost applies to timed lab experiments; gameplay already uses source settings')
    if args.cost_only and not args.paired_cost:parser.error('Cost-only requires a paired comparison')
    if args.wait_idle and not (args.paired_cost or args.gameplay):parser.error('Idle waiting requires paired cost or physical gameplay')
    if args.paired_cost:args.cases={'grass':'filtered_optimized','fern':'fern_optimized','fern_surface':'fern_optimized','complete':'fern_cluster','details':'fern_cluster,stone_removed,flower_removed,combined_filtered,flower_bounded_edge,flower_bounded_canopy,flower_no_ribs','detail_clustered':'fern_cluster,stone_removed,flower_removed,detail_clustered','detail_lookup':'fern_cluster,stone_removed,flower_removed,detail_lookup','detail_runtime':'fern_cluster,stone_removed,flower_removed,detail_runtime','detail_early':'fern_cluster,stone_removed,flower_removed,detail_early','details_split':'fern_cluster,stone_removed,flower_removed,stone_filtered,flower_clustered'}.get(args.paired_cost,args.paired_cost)
    plan = json.loads(PLAN.read_text())
    configs = configurations(plan)
    selected = set(args.cases.split(',')) if args.cases else set(configs)
    motion_cases=sorted((selected|{'reference','filtered_optimized'})&set(plan['capture_cases']))
    if not (args.list or args.gameplay or args.cost_only) and len(motion_cases)>6:
        parser.error('At most six full motion captures fit the unchanged packet budget; split the selected cases into smaller batches')
    unknown = selected - configs.keys()
    if unknown:
        parser.error('Unknown cases: ' + ', '.join(sorted(unknown)))
    by_id = {c['id']: c for c in plan['cases']}
    detail_batch=any(configs[name].get('detail_probe','none')!='none' for name in selected)
    if detail_batch:
        # All configurations are still resolved, and close-view guards remain.
        # Stone/flower comparisons hold the validated grass/fern baseline fixed;
        # replaying every historical grass/fern intervention adds no new control.
        selected.add('fern_cluster')
    else:
        for name in tuple(selected):
            while name is not None:
                selected.add(name)
                name = by_id[name]['parent']
    selected.add('reference')
    ids = [c['id'] for c in plan['cases'] if c['id'] in selected]
    if args.list:
        for case in plan['cases']:
            if case['id'] in selected:
                print(f"{case['id']}: parent={case['parent']}; change={case['change']}; {case['question']}")
        return 0
    jobs = active_render_jobs()
    # The image-only driver freezes time/simulation, checks exact reference
    # repeats and has no timing windows. Other jobs invalidate cost qualification,
    # not this scoped image experiment; resource limits still apply unchanged.
    if jobs and not (args.visual_only or args.wait_idle):
        print('Lab not launched: another render job/session is active: ' + json.dumps(jobs))
        return 2
    # Admission runs before the shared runner allocates its receipt, too. Limits
    # are never widened. No new world, export or isolated source copy is requested.
    from development_storage import admit
    try:
        admit(ROOT, report_bytes=20 * 2**20, world_bytes=0)
    except OSError as error:
        print('Lab not launched: ' + str(error))
        return 2
    run_id=uuid.uuid4().hex
    test='vegetation_gameplay' if args.gameplay else 'vegetation_lab'
    extras=(['--gameplay-source-slot='+args.slot] if args.gameplay else
            ['--stability-source-slot='+args.slot,'--lab-cases='+','.join(ids),'--lab-motion-cases='+','.join(motion_cases)])
    if args.opaque_control:extras.append('--opaque-control')
    if args.previous_filter_control:extras.append('--previous-filter-control')
    if args.fern_trial:extras.append('--fern-trial')
    if args.fern_cluster_trial:extras.append('--fern-cluster-trial')
    if args.grounded_view:extras.append('--lab-grounded-view')
    if args.paired_cost:extras.append('--lab-paired-cost='+args.paired_cost)
    if args.visual_only:extras.append('--lab-visual-only')
    if args.source_cost:extras.append('--lab-source-cost')
    if args.cost_only:extras.append('--lab-cost-only')
    if args.wait_idle:extras.append('--lab-wait-launch' if args.gameplay else '--lab-wait-idle')
    command = [sys.executable, str(ROOT / 'tools/run_godot_check.py'), test,
               '--isolated-render', '--timeout', '240' if args.gameplay else '600', '--require', test.upper()+' failures=0',
               '--', *extras,'--lab-run-id='+run_id]
    before=set((ROOT/'reports/checks').iterdir())
    observed=[];gpu_telemetry=[];started=time.time();overlap=False;monitor_error=None
    live_folder=None;last_busy=0.0;idle_since=0.0
    nvidia=shutil.which('nvidia-smi') if args.paired_cost else None
    process=subprocess.Popen(command,cwd=ROOT)
    while process.poll() is None:
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                jobs=active_render_jobs(run_id)
                if jobs:
                    last_busy=time.time();idle_since=0.0
                    overlap=True
                    if len(observed)<120:observed.append(dict(seconds=time.time()-started,jobs=jobs))
                elif not idle_since:idle_since=time.time()
                if args.wait_idle and not args.gameplay:
                    if live_folder is None:
                        for folder in set((ROOT/'reports/checks').iterdir())-before:
                            try:record=json.loads((folder/'run.json').read_text())
                            except (OSError,ValueError):continue
                            if '--lab-run-id='+run_id in record.get('command',[]):live_folder=folder;break
                    if live_folder:
                        temporary=live_folder/'interference.live.pending'
                        temporary.write_text(json.dumps(dict(unix_s=time.time(),last_busy_unix_s=last_busy,idle_since_unix_s=idle_since,monitor_ok=monitor_error is None)))
                        temporary.replace(live_folder/'interference.live.json')
                if nvidia and len(gpu_telemetry)<120:
                    sample=subprocess.run([nvidia,'--query-gpu=clocks.gr,clocks.sm,clocks.mem,pstate,power.draw,temperature.gpu,utilization.gpu','--format=csv,noheader,nounits'],capture_output=True,text=True,timeout=3)
                    gpu_telemetry.append(dict(seconds=time.time()-started,unix_s=time.time(),returncode=sample.returncode,csv=sample.stdout.strip()[:1024]))
            except (OSError,ValueError,subprocess.SubprocessError) as error:
                monitor_error=str(error)
    for folder in set((ROOT/'reports/checks').iterdir())-before:
        receipt=folder/'run.json'
        if not receipt.is_file():continue
        record=json.loads(receipt.read_text())
        if '--lab-run-id='+run_id not in record.get('command',[]):continue
        witness=dict(overlap_observed=overlap,observations=observed,monitor_error=monitor_error,
                     monitor_started_unix_s=started,
                     scope='Windows render-job command inventory every five seconds; short overlap or unrelated GPU applications may be missed.')
        if args.paired_cost:witness['nvidia_clock_power_temperature_utilization']=gpu_telemetry
        payload=json.dumps(witness,indent=2)
        if len(payload.encode())>128*1024:raise ValueError('Interference witness exceeds metadata allowance')
        (folder/'interference.json').write_text(payload+'\n')
    return process.returncode


if __name__ == '__main__':
    raise SystemExit(main())
