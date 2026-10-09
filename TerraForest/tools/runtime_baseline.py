"""Record the existing short 1080p world benchmark on the current host, without changing settings."""
# SPDX-License-Identifier: 0BSD
from pathlib import Path
import argparse
import csv
import ctypes
import datetime
import hashlib
import json
import re
import subprocess
import time
from windows_process_metrics import ProcessMetrics

ROOT = Path(__file__).resolve().parents[1]
FLAGS = getattr(subprocess, 'CREATE_NO_WINDOW', 0)

def capture(command):
    try:
        r = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=15, creationflags=FLAGS)
        return {'exit': r.returncode, 'stdout': r.stdout.strip(), 'stderr': r.stderr.strip()}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {'error': str(exc)}

def battery():
    class Status(ctypes.Structure):
        _fields_ = [('ac', ctypes.c_ubyte), ('flags', ctypes.c_ubyte), ('percent', ctypes.c_ubyte),
                    ('reserved', ctypes.c_ubyte), ('seconds', ctypes.c_ulong), ('full_seconds', ctypes.c_ulong)]
    state = Status()
    return {'ac': state.ac, 'battery_percent': state.percent} if ctypes.windll.kernel32.GetSystemPowerStatus(ctypes.byref(state)) else {'error': 'unavailable'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=r'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
    args = parser.parse_args()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    folder = ROOT/'reports/runtime_baseline'/stamp
    folder.mkdir(parents=True)
    prefix = folder/'world'
    command = [args.godot, '--path', str(ROOT), '--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan',
               '--fullscreen', '--resolution', '1920x1080', '--max-fps', '60', '--script', 'res://tests/runtime_baseline.gd',
               '--', '--benchmark', '--temporary', '--seconds=5', '--max-fps=60', '--world-generator=1', '--world-seed=1703',
               f'--derived-cache={(folder/"derived_cache").as_posix()}', f'--out={prefix.as_posix()}']
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in [ROOT/'project.godot', ROOT/'demo/benchmark.gd', ROOT/'tests/runtime_baseline.gd',
                        ROOT/'tools/runtime_baseline.py', ROOT/'tools/windows_process_metrics.py',
                        *sorted((ROOT/'addons').glob('*/bin/*.dll'))]}
    manifest = {'utc': stamp, 'revision': capture(['git', 'rev-parse', 'HEAD']), 'worktree': capture(['git', 'status', '--short']),
                'command': command, 'source_and_dll_sha256': hashes, 'engine_version': capture([args.godot, '--version']),
                'cpu': capture(['powershell', '-NoProfile', '-Command', 'Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors | ConvertTo-Json']),
                'ram': capture(['powershell', '-NoProfile', '-Command', 'Get-CimInstance Win32_PhysicalMemory | Select-Object Capacity,ConfiguredClockSpeed | ConvertTo-Json']),
                'power_plan': capture(['powercfg', '/getactivescheme']), 'processor_policy': capture(['powercfg', '/query', 'SCHEME_CURRENT', 'SUB_PROCESSOR']),
                'battery_before': battery(), 'nvidia_before': capture(['nvidia-smi', '--query-gpu=name,driver_version,pstate,power.draw,temperature.gpu,utilization.gpu', '--format=csv']),
                'vendor_thermal_mode': 'unknown; user settings unchanged', 'windows_power_overlay': 'unknown; user settings unchanged',
                'cpu_measurement': 'Windows process kernel+user CPU time / wall interval; machine percent divides by active logical processors. System busy excludes idle from GetSystemTimes. Not frequency-weighted Task Manager utility.',
                'cpu_package_power_w': None, 'cpu_package_temperature_c': None,
                'cache': 'Fresh temporary world and isolated initially empty derived terrain cache per run; existing engine shader/import caches retained.',
                'scope': 'Eight fixed 5-second phases after 3-second warmups; short reference, not endurance, multiplayer, large-city or thermal equilibrium qualification.'}
    (folder/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print('BASELINE_OUTPUT '+str(folder), flush=True)
    start = time.monotonic()
    timed_out = False
    cpu_samples = []
    with (folder/'engine.log').open('w', encoding='utf-8') as log, (folder/'gpu.jsonl').open('w', encoding='utf-8') as samples:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, creationflags=FLAGS)
        metrics = None
        try:
            metrics = ProcessMetrics(process.pid)
        except OSError as exc:
            metrics_error = str(exc)
        try:
            while process.poll() is None:
                try:
                    cpu = metrics.sample() if metrics else {'error': metrics_error}
                except OSError as exc:
                    cpu = {'error': str(exc)}
                cpu_samples.append(cpu)
                sample = {'elapsed_s': time.monotonic()-start, 'battery': battery(), 'cpu': cpu,
                          'gpu': capture(['nvidia-smi', '--query-gpu=timestamp,pstate,power.draw,temperature.gpu,utilization.gpu,memory.used,clocks.gr,clocks.mem', '--format=csv,noheader,nounits'])}
                samples.write(json.dumps(sample)+'\n'); samples.flush()
                if time.monotonic()-start > 180:
                    timed_out = True; process.kill(); process.wait(); break
                time.sleep(1)
        finally:
            if metrics: metrics.close()
    summary_file = Path(str(prefix)+'.summary.csv')
    observations_file = Path(str(prefix)+'.observations.jsonl')
    rows = list(csv.DictReader(summary_file.open())) if summary_file.exists() else []
    observations = [json.loads(line) for line in observations_file.read_text().splitlines()] if observations_file.exists() else []
    measured = [r for r in observations if r['state']=='measuring']
    presentation_ok = {r['phase'] for r in measured}==set(range(8)) and all(r['fair_graphical_sample'] and r['fps_cap_actual']==60 and r['vsync_mode']==1 and r['focused'] for r in measured)
    errors = bool(re.search(r'(?m)^(SCRIPT ERROR|ERROR:|WARNING: ObjectDB instances leaked)', (folder/'engine.log').read_text(encoding='utf-8')))
    complete = process.returncode==0 and not timed_out and len(rows)==8 and not errors
    phase_cpu = []
    for index, row in enumerate(rows):
        stamps = [o['utc_unix_s'] for o in measured if o['phase']==index]
        # Keep only complete CPU intervals inside observed measuring windows;
        # never attribute startup/transition work to an adjacent phase.
        selected = [c for c in cpu_samples if 'interval_s' in c and stamps and
                    c['interval_start_utc_unix_s']>=min(stamps) and c['utc_unix_s']<=max(stamps)]
        values = sorted(c['process_machine_percent'] for c in selected)
        phase_cpu.append({'phase': row['phase'], 'samples': len(selected),
                          'process_machine_mean_percent': 100*sum(c['process_cpu_ms'] for c in selected)/1000/sum(c['interval_s'] for c in selected)/selected[0]['logical_processors'] if selected else None,
                          'process_machine_max_percent': max(values) if values else None,
                          'process_one_core_max_percent': max(c['process_one_core_percent'] for c in selected) if selected else None,
                          'system_busy_mean_percent': sum(c['system_busy_percent'] for c in selected)/len(selected) if selected else None})
    cpu_valid = len(phase_cpu)==8 and all(p['samples']>=2 for p in phase_cpu) and not any('error' in c for c in cpu_samples)
    valid_memory = [c for c in cpu_samples if 'working_set_bytes' in c]
    result = {'complete': complete, 'exit': process.returncode, 'timed_out': timed_out, 'elapsed_s': time.monotonic()-start,
              'presentation_samples_valid': presentation_ok, 'engine_errors': errors, 'phases': rows, 'battery_after': battery(),
              'cpu_samples_valid': cpu_valid, 'cpu_phases': phase_cpu,
              'process_working_set_peak_mib': max(c['working_set_bytes'] for c in valid_memory)/1048576 if valid_memory else None,
              'process_private_commit_peak_mib': max(c['private_commit_bytes'] for c in valid_memory)/1048576 if valid_memory else None,
              'note': 'GPU telemetry is whole-device, including other applications. Frame times include pacing; this is a reference measurement, not proof of spare performance or sustained cooling.'}
    (folder/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2), flush=True)
    return 0 if complete and presentation_ok and cpu_valid else 1

if __name__ == '__main__':
    raise SystemExit(main())
