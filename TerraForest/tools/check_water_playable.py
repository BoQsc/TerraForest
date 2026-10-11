# SPDX-License-Identifier: 0BSD
"""Full-world water roundtrip in an isolated real save slot (never a user world)."""
import argparse, datetime, json, os, uuid
from pathlib import Path
from run import ROOT, parse_args
from run_godot_check import command_for, execute
p=argparse.ArgumentParser();p.add_argument('--headless',action='store_true');args=p.parse_args()
engine=parse_args([])[0].godot
folder=ROOT/'reports/checks'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ');folder.mkdir(parents=True)
command,cache=command_for(engine,'water_playable',folder,['--gameplay-construction'],args.headless)
command.remove('--temporary')
slot=next(a.split('=',1)[1] for a in command if a.startswith('--world-slot='))
result=execute(command,folder,90,'REGIONAL_WATER_WORLD failures=0')
(folder/'run.json').write_text(json.dumps(result,indent=2))
print(('PASS ' if result['passed'] else 'FAIL ')+str(folder))
# Only the unique test-owned files; keep failures for diagnosis.
if result['passed']:
 base=Path(os.environ['APPDATA'])/'Godot/app_userdata/TerraForest/worlds'
 for suffix in ('.trw','.trw.bak','.trw.lock'):
  path=base/(slot+suffix)
  if path.is_file():path.unlink()
raise SystemExit(0 if result['passed'] else 1)
