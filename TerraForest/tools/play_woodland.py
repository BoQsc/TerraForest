# SPDX-License-Identifier: 0BSD
"""Open a disposable dense woodland patch for visual judgment and interaction."""
import uuid
from run import ROOT, parse_args, launch_details
from play_checkpoint import record_and_run
import datetime


def main():
    args, extra = parse_args()
    if extra:
        raise SystemExit('Only normal launcher options are accepted; preview owns its cache and save policy.')
    token = uuid.uuid4().hex
    args.temporary = True
    args.slot = 'woodland_' + token
    details = launch_details(args, ['--ground-cover', '--woodland-inspect',
                                    '--derived-cache=user://woodland_patch_' + token])
    command = details['command']
    scene = command.index('res://demo/' + args.scene + '.tscn')
    command[scene:scene+1] = ['--script', 'res://demo/woodland_patch.gd']
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT/'reports/playtests'/stamp
    command[1:1] = ['--log-file', str(folder/'engine.log')]
    details.update(utc=stamp, label='Disposable woodland density review',
                   notes='Temporary unsaved world; snapshot writes blocked. New cache retained. No GPU qualification.')
    if args.dry_run:
        import json
        print(json.dumps(details, indent=2))
        return 0
    return record_and_run(details, folder, details['label'])


if __name__ == '__main__':
    raise SystemExit(main())
