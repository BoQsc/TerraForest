# SPDX-License-Identifier: 0BSD
import argparse
import datetime
import hashlib
import json
import subprocess
from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native

parser = argparse.ArgumentParser()
parser.add_argument('--pack', action='store_true')
parser.add_argument('--verbose', action='store_true')
parser.add_argument('--reuse-report', default='reports/frontier_expedition/20261102T110842820893Z')
args = parser.parse_args()
source = (ROOT / args.reuse_report).resolve()
if not source.is_relative_to(ROOT / 'reports/frontier_expedition'):
    parser.error('Use an owned expedition report')
slot = json.loads((source / 'world.json').read_text())['slot']
if not slot.startswith('Expedition_1703_'):
    parser.error('Not an owned expedition fixture')
folder = ROOT / 'reports/menu_transition' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
folder.mkdir(parents=True)
(folder / '.gdignore').touch()
script = ROOT / 'tests/menu_transition.gd'
native = verify_pack_native() if args.pack else {}
if args.pack:
    script = folder / 'driver.gd'
    script.write_bytes((ROOT / 'tests/menu_transition.gd').read_bytes())
config, _ = parse_args([])
command = [config.godot, '--path', str(ROOT / 'dist' if args.pack else ROOT), '--windowed', '--position', '-2400,-1600', '--resolution', '1920x1080', '--max-fps', '60', '--log-file', str(folder / 'engine.log'), '--script', str(script), '--', '--ui-output=' + folder.as_posix(), '--ui-slot=' + slot]
if args.pack:
    command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
if args.verbose:
    command.insert(1, '--verbose')
original = subprocess.Popen
def nonactivating(*arguments, **keywords):
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 4
    keywords['startupinfo'] = startup
    return original(*arguments, **keywords)
subprocess.Popen = nonactivating
try:
    result = execute(command, folder, 240, 'MENU_TRANSITION failures=0', require_resource_budget=True)
finally:
    subprocess.Popen = original
record = {'command': command, 'result': result, 'native_sha256': native, 'test_sha256': hashlib.sha256(script.read_bytes()).hexdigest()}
if args.pack:
    record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
(folder / 'run.json').write_text(json.dumps(record, indent=2)+'\n')
print(('PASS ' if result['passed'] else 'FAIL ')+str(folder))
raise SystemExit(0 if result['passed'] else 1)
