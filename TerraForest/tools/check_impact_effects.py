# SPDX-License-Identifier: 0BSD
"""Check actual impacts in source or exported pack, with isolated settings and saves."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
from run import ROOT, parse_args
from run_godot_check import command_for, execute
from play_checkpoint import revision_metadata

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--pack', action='store_true')
parser.add_argument('--off', action='store_true')
options = parser.parse_args()
config, _ = parse_args([])
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
folder = ROOT/'reports/checks'/(stamp+'_impact_effects'+('_pack' if options.pack else '_source')+('_off' if options.off else ''))
folder.mkdir(parents=True)
extra = ['--gameplay-construction', '--ground-cover', '--no-zombies', '--effects-evidence='+str(folder/'captures')]
if options.off:
    extra.append('--no-impact-effects')
command, cache = command_for(config.godot, 'impact_effects_world', folder, extra)
if options.pack:
    driver = folder/'impact_external.gd'
    driver.write_bytes((ROOT/'tests/impact_effects_world.gd').read_bytes())
    command[command.index('--path')+1] = str(ROOT/'dist')
    command[command.index('--script')+1] = str(driver)
    command[1:1] = ['--main-pack', str(ROOT/'dist/TerraForest.pck')]
record = dict(command=command, cache=cache, utc=stamp,
              test_sha256=hashlib.sha256((ROOT/'tests/impact_effects_world.gd').read_bytes()).hexdigest(),
              engine_sha256=hashlib.sha256(Path(config.godot).read_bytes()).hexdigest(), **revision_metadata())
if options.pack:
    record['pack_sha256'] = hashlib.sha256((ROOT/'dist/TerraForest.pck').read_bytes()).hexdigest()
manifest = folder/'run.json'
manifest.write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
record['result'] = execute(command, folder, 100, 'failures=0')
manifest.write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
print(('PASS ' if record['result']['passed'] else 'FAIL ')+str(folder), flush=True)
raise SystemExit(0 if record['result']['passed'] else 1)
