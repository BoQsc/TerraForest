# SPDX-License-Identifier: 0BSD
import argparse
import datetime
import hashlib
import json
import subprocess
from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native

parser = argparse.ArgumentParser()
parser.add_argument('stage', choices=['wakeup', 'zombie', 'guidance', 'wakeup_runtime'])
parser.add_argument('--pack', action='store_true')
args = parser.parse_args()
if args.pack and args.stage == 'wakeup':
    parser.error('Authoring previews are deliberately excluded from exports; use wakeup_runtime')
config, _ = parse_args([])
folder = ROOT / 'reports/expedition_motion' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
folder.mkdir(parents=True)
script = {'wakeup': 'tools/review_player_wakeup.gd', 'zombie': 'tests/zombie_alert.gd', 'guidance': 'tests/quest_guidance.gd', 'wakeup_runtime': 'tests/wakeup_runtime.gd'}[args.stage]
command = [config.godot, '--path', str(ROOT), '--windowed', '--position', '-2400,-1600', '--resolution', '1280x720', '--max-fps', '60', '--log-file', str(folder / 'engine.log'), '--script', 'res://' + script, '--', '--review-output=' + folder.as_posix()]
native = verify_pack_native() if args.pack else {}
if args.pack:
    parent = folder / 'zombie_impacts.gd'
    parent.write_bytes((ROOT / 'tests/zombie_impacts.gd').read_bytes())
    driver = folder / 'driver.gd'
    driver.write_text((ROOT / script).read_text().replace('res://tests/zombie_impacts.gd', parent.as_posix()), encoding='utf-8')
    command[command.index('--script') + 1] = str(driver)
    command[command.index('--path') + 1] = str(ROOT / 'dist')
    command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
if args.stage == 'wakeup_runtime':
    command.insert(1, '--headless')
original = subprocess.Popen
def nonactivating(*arguments, **keywords):
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 4
    keywords['startupinfo'] = startup
    return original(*arguments, **keywords)
subprocess.Popen = nonactivating
try:
    result = execute(command, folder, 300, {'wakeup': 'PLAYER_WAKEUP_REVIEW frames=150', 'zombie': 'ZOMBIE_ALERT checks=', 'guidance': 'QUEST_GUIDANCE checks=', 'wakeup_runtime': 'WAKEUP_RUNTIME checks='}[args.stage], require_resource_budget=args.stage != 'wakeup_runtime')
finally:
    subprocess.Popen = original
record = {'command': command, 'result': result, 'native_sha256': native, 'test_sha256': hashlib.sha256((ROOT / script).read_bytes()).hexdigest()}
if args.pack:
    record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
(folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
print(('PASS ' if result['passed'] else 'FAIL ') + str(folder))
raise SystemExit(0 if result['passed'] else 1)
