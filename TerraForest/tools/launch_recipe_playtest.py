# SPDX-License-Identifier: 0BSD
"""Open the protected save from a successful island QA receipt for human review.

Declares 8 MiB of launch/engine logs and no new world, export or source copy.
The user-owned save and review receipt remain protected; this launcher never
retires them. Manual screenshots/edits made by the player belong to that review.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import subprocess

from development_storage import admit
from maintain_performance_artifacts import no_game_processes
from retained_artifacts import confined, digest
from run import ROOT, parse_args


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('--godot')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    report = confined(args.report.resolve(), ROOT / 'reports/inhabited_island_world')
    receipt = json.loads((report / 'run.json').read_text())
    identity = json.loads((report / 'slot.json').read_text())
    slot = identity.get('slot', '')
    if (receipt.get('purpose') != 'normal inhabited island generation and fresh restore'
            or not receipt.get('functional_passed') or not receipt.get('human_playtest_owned')
            or not re.fullmatch(r'Island_1703_[0-9a-f]{8}', slot)
            or not (report / '.retain').is_file()):
        raise ValueError('A completed functional check and explicit protected human handoff are required')
    for name, expected in receipt['native_sha256'].items():
        if digest(confined(ROOT / name, ROOT / 'addons')) != expected:
            raise ValueError('Native code changed since the integrated check: ' + name)
    world = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds' / (slot + '.trw')
    if not world.is_file():
        raise ValueError('The protected playtest save is missing')
    engine = Path(parse_args(['--godot', args.godot] if args.godot else [])[0].godot)
    direct = engine.parent / 'godot.windows.opt.tools.64.exe'
    if direct.is_file():
        engine = direct
    command = [str(engine), '--path', str(ROOT), '--windowed', '--resolution', '1600x900',
               '--max-fps', '60', 'res://demo/world.tscn', '--', '--world-slot=' + slot,
               '--world-generator=36', '--world-seed=1703', '--human-playtest']
    if args.dry_run:
        print(json.dumps({'slot': slot, 'command': command, 'new_world': False,
                          'strict_qa_passed': receipt.get('passed', False)}))
        return 0
    no_game_processes()
    admission = admit(ROOT, report_bytes=8 * 2**20, world_bytes=0)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = report / ('human_' + stamp)
    folder.mkdir()
    command[1:1] = ['--log-file', str(folder / 'engine.log')]
    with (folder / 'console.log').open('w', encoding='utf-8') as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    record = {'pid': process.pid, 'command': command, 'slot': slot, 'new_world': False,
              'save_sha256_at_launch': digest(world), 'qa_receipt_sha256': digest(report / 'run.json'),
              'admission': admission, 'strict_qa_passed': receipt.get('passed', False),
              'status': 'started; verify HUMAN_PLAYTEST_READY in engine.log',
              'retention': 'User-owned playtest save and review evidence; no automatic retirement'}
    (folder / 'launch.json').write_text(json.dumps(record, indent=2))
    print(json.dumps({'pid': process.pid, 'slot': slot, 'report': str(folder)}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
