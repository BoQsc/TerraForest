"""Record the existing short 1080p world benchmark on the current host, without changing settings."""
# SPDX-License-Identifier: 0BSD
from pathlib import Path
import argparse
import csv
import ctypes
import datetime
import hashlib
import json
import subprocess
import time

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
               '--', '--benchmark', '--temporary', '--seconds=5', '--max-fps=60', '--world-generator=1', '--world-seed=1703', f'--out={prefix.as_posix()}']
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in [ROOT/'project.godot', ROOT/'demo/benchmark.gd', ROOT/'tests/runtime_baseline.gd',
                        *sorted((ROOT/'addons').glob('*/bin/*.dll'))]}
    manifest = {'utc': stamp, 'revision': capture(['git', 'rev-parse', 'HEAD']), 'worktree': capture(['git', 'status', '--short']),
                'command': command, 'source_and_dll_sha256': hashes, 'engine_version': capture([args.godot, '--version']),
                'cpu': capture(['powershell', '-NoProfile', '-Command', 'Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors | ConvertTo-Json']),
                'ram': capture(['powershell', '-NoProfile', '-Command', 'Get-CimInstance Win32_PhysicalMemory | Select-Object Capacity,ConfiguredClockSpeed | ConvertTo-Json']),
                'power_plan': capture(['powercfg', '/getactivescheme']), 'processor_policy': capture(['powercfg', '/query', 'SCHEME_CURRENT', 'SUB_PROCESSOR']),
                'battery_before': battery(), 'nvidia_before': capture(['nvidia-smi', '--query-gpu=name,driver_version,pstate,power.draw,temperature.gpu,utilization.gpu', '--format=csv']),
                'vendor_thermal_mode': 'unknown; user settings unchanged', 'windows_power_overlay': 'unknown; user settings unchanged',
                'cache': 'Fresh temporary world; existing engine shader/import caches retained. Derived cache state recorded in observations.',
                'scope': 'Eight fixed 5-second phases after 3-second warmups; short reference, not endurance, multiplayer, large-city or thermal equilibrium qualification.'}
    (folder/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print('BASELINE_OUTPUT '+str(folder), flush=True)
    start = time.monotonic()
    timed_out = False
    with (folder/'engine.log').open('w', encoding='utf-8') as log, (folder/'gpu.jsonl').open('w', encoding='utf-8') as samples:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, creationflags=FLAGS)
        while process.poll() is None:
            sample = {'elapsed_s': time.monotonic()-start, 'battery': battery(),
                      'gpu': capture(['nvidia-smi', '--query-gpu=timestamp,pstate,power.draw,temperature.gpu,utilization.gpu,memory.used,clocks.gr,clocks.mem', '--format=csv,noheader,nounits'])}
            samples.write(json.dumps(sample)+'\n'); samples.flush()
            if time.monotonic()-start > 180:
                timed_out = True; process.kill(); process.wait(); break
            time.sleep(1)
    summary_file = Path(str(prefix)+'.summary.csv')
    observations_file = Path(str(prefix)+'.observations.jsonl')
    rows = list(csv.DictReader(summary_file.open())) if summary_file.exists() else []
    observations = [json.loads(line) for line in observations_file.read_text().splitlines()] if observations_file.exists() else []
    measured = [r for r in observations if r['state']=='measuring']
    presentation_ok = bool(measured) and all(r['fair_graphical_sample'] and r['fps_cap_actual']==60 and r['vsync_mode']==1 and r['focused'] for r in measured)
    complete = process.returncode==0 and not timed_out and len(rows)==8
    result = {'complete': complete, 'exit': process.returncode, 'timed_out': timed_out, 'elapsed_s': time.monotonic()-start,
              'presentation_samples_valid': presentation_ok, 'phases': rows, 'battery_after': battery(),
              'note': 'GPU telemetry is whole-device, including other applications. Frame times include pacing; this is a reference measurement, not proof of spare performance or sustained cooling.'}
    (folder/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2), flush=True)
    return 0 if complete and presentation_ok else 1

if __name__ == '__main__':
    raise SystemExit(main())
