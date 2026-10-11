# SPDX-License-Identifier: 0BSD
"""Prepare the ordinary saved water world's spawn area before graphical play."""
import subprocess
import sys
from run import parse_args, launch_details

def main():
    args, extra = parse_args(sys.argv[1:])
    if args.temporary:
        raise SystemExit('Preparation requires a saved world; omit --temporary.')
    if args.slot is None:
        args.slot = 'water_gameplay_v2'
    extra = [*extra, '--water-gameplay', '--gameplay-construction']
    details = launch_details(args, extra)
    command = details['command']
    scene = command.index('res://demo/world.tscn')
    command[scene:scene+1] = ['--headless', '--script', 'res://tools/prepare_water_world.gd']
    if args.dry_run:
        import json
        print(json.dumps({'slot':args.slot,'command':command}, indent=2))
        return 0
    print(f"Preparing saved spawn area: {args.slot}. Existing terrain and water quantities are retained.",flush=True)
    return subprocess.call(command)
if __name__ == '__main__':
    raise SystemExit(main())
