"""Launch the labeled human checkpoint, or perform its short startup check."""
# SPDX-License-Identifier: 0BSD
import argparse
import datetime
import hashlib
import json
import re
import subprocess
from pathlib import Path
from run import ROOT, parse_args, launch_details

LABEL = 'Human checkpoint 2026-10-09'
SLOT = 'human_checkpoint_20261009'

def revision_metadata():
    # Playing a local project must not require developer-only tools on PATH.
    try:
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT,
                                           text=True, stderr=subprocess.PIPE, timeout=5).strip()
        changes = subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT,
                                          text=True, stderr=subprocess.PIPE, timeout=5).splitlines()
        return {'revision': revision, 'worktree_changes': changes, 'git_metadata_available': True}
    except (OSError, subprocess.SubprocessError) as error:
        return {'revision': None, 'worktree_changes': None, 'git_metadata_available': False,
                'git_metadata_note': f'{type(error).__name__}: Git metadata unavailable; native hashes still recorded.'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    options = parser.parse_args()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    args, _ = parse_args(['--slot', SLOT if not options.smoke else 'human_startup_'+stamp[:-1],
                         '--generator', '1', '--seed', '1703',
                         *(['--godot', options.godot] if options.godot else [])])
    details = launch_details(args, ['--human-playtest', '--playtest-checkpoint'])
    folder = ROOT / 'reports' / 'playtests' / stamp
    command = details['command']
    if options.smoke:
        index = command.index('res://demo/world.tscn')
        command[index:index+1] = ['--script', 'res://tests/playtest_startup.gd']
    command[1:1] = ['--log-file', str(folder / 'engine.log')]
    details.update(label=LABEL, utc=stamp, automatic_startup_check=options.smoke,
                   active_profile='Default terrain, forest, native blocks/objects, free editor, player/inventory and vehicle integration',
                   inactive=['experimental regional/snapshot terrain flags', 'automatic model transfer scheduling', 'model metadata startup'],
                   notes='60 FPS is the target/cap, not a measured guarantee; no hardware or power settings are changed.')
    if options.dry_run:
        print(json.dumps(details, indent=2));return 0
    folder.mkdir(parents=True)
    details.update(revision_metadata())
    details['native_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted((ROOT / 'addons').glob('*/bin/*.dll'))}
    details['command'] = command
    manifest = folder / 'launch.json'
    manifest.write_text(json.dumps(details, indent=2)+'\n', encoding='utf-8')
    print(f'{LABEL}: 1920x1080 fullscreen, VSync, 60 FPS cap.', flush=True)
    print(f'Saved-world slot: {details["slot"]}. F5 saves; F9 reloads.', flush=True)
    print(f'Log and launch record: {folder}', flush=True)
    with (folder / 'console.log').open('w', encoding='utf-8') as output:
        process = subprocess.Popen(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                   creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        details['pid'] = process.pid
        manifest.write_text(json.dumps(details, indent=2)+'\n', encoding='utf-8')
        try:
            code = process.wait(timeout=90 if options.smoke else None)
        except subprocess.TimeoutExpired:
            process.kill();process.wait();code = 124
    if options.smoke and code == 0:
        log = (folder / 'console.log').read_text(encoding='utf-8', errors='replace')
        if re.search(r'(?m)^(?:SCRIPT ERROR|ERROR:|FAIL |WARNING: ObjectDB instances leaked)', log) or 'PASS PLAYTEST_STARTUP ' not in log:
            code = 1
    details['exit_code'] = code
    details['status'] = 'exited; inspect engine.log for readiness and errors'
    manifest.write_text(json.dumps(details, indent=2)+'\n', encoding='utf-8')
    print(f'Game exited ({code}). Logs: {folder}', flush=True)
    return code

if __name__ == '__main__':
    raise SystemExit(main())
