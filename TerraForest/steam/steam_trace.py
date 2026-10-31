#!/usr/bin/env python3
"""Measure what Steam actually does while it shuts down and boots.

Samples the watched process set every 100 ms across one real restart and prints a
timestamped timeline plus the duration of each observed phase. The same transition
it measures (gone -> steam.exe -> helpers -> settled) is what the progress bar's
start stage reports, so the labels are measurements rather than guesses.

Usage:
    python steam/steam_trace.py             # observe the running Steam, no restart
    python steam/steam_trace.py --restart   # one real stop/start cycle
    python steam/steam_trace.py --restart --json out.json
"""
from pathlib import Path
import argparse
import json
import subprocess
import sys
import time

TOOL = Path(__file__).resolve().parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))
import steam_shortcuts as steam  # noqa: E402

SAMPLE = 0.1
SETTLE = 2.0


def steam_dir():
    """The Steam install the shortcuts live in, from the registry."""
    for candidate in steam.steam_roots():
        if (candidate/'userdata').is_dir():
            return candidate
    raise SystemExit('Steam install not found')


def watch(timeout, settle=SETTLE, label=''):
    """Sample until the process set has been stable for `settle` seconds."""
    started = time.time()
    events = []
    previous = None
    stable_since = started
    while True:
        now = set(steam.steam_running())
        if previous is None or now != previous:
            events.append({'at': round(time.time()-started, 2), 'set': sorted(now)})
            previous = now
            stable_since = time.time()
        elif time.time()-stable_since >= settle:
            break
        if time.time()-started >= timeout:
            break
        time.sleep(SAMPLE)
    return {'label': label, 'started': started, 'events': events,
            'elapsed': round(time.time()-started, 2)}


def phases(timeline):
    """Derive named phases from the observed transitions."""
    marks = timeline['events']
    found = []
    for index, event in enumerate(marks):
        following = marks[index+1]['at'] if index+1 < len(marks) else timeline['elapsed']
        found.append({'phase': describe(event['set']), 'from': event['at'],
                      'to': following, 'seconds': round(following-event['at'], 2),
                      'processes': event['set']})
    return found


def describe(names):
    names = set(names)
    if not names:
        return 'no Steam processes'
    if 'steam.exe' not in names:
        return 'helpers only (client gone)'
    helpers = sum(1 for name in names if name == 'steamwebhelper.exe')
    return f'client up, {helpers} helper(s)' + (', overlay' if steam.GAME_MARKER in names else '')


def observe(seconds=6.0):
    timeline = watch(seconds, settle=seconds, label='steady state')
    print(f"observed : {describe(timeline['events'][-1]['set'])}")
    for phase in phases(timeline):
        print(f"  {phase['phase']:28} {phase['seconds']:5.2f}s  {', '.join(phase['processes']) or '-'}")
    return 0


def restart(trace_json=None):
    steam_root = steam_dir()
    executable = steam_root/'steam.exe'
    if not executable.is_file():
        raise SystemExit(f'{executable}: steam.exe not found')
    before = watch(SETTLE, label='before')
    print(f"before   : {describe(before['events'][-1]['set'])}")

    # The tracer drives shutdown and launch itself: letting start_steam() wait would
    # hide the very transitions this measures.
    t0 = time.time()
    subprocess.run([str(executable), '-shutdown'], timeout=30, stdin=subprocess.DEVNULL,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    down = watch(60, label='shutdown')
    stop_seconds = round(time.time()-t0, 2)
    print(f"stopped  : {describe(down['events'][-1]['set'])} in {stop_seconds:.2f}s")
    for phase in phases(down):
        print(f"  +{phase['from']:5.2f}s  {phase['phase']:34} {phase['seconds']:5.2f}s  "
              f"{', '.join(phase['processes']) or '-'}")

    t1 = time.time()
    subprocess.Popen([str(executable), '-silent'], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=True,
                     creationflags=steam.DETACHED_PROCESS | steam.CREATE_NEW_PROCESS_GROUP)
    boot = watch(60, label='boot')
    boot_seconds = round(time.time()-t1, 2)
    print(f"started  : {describe(boot['events'][-1]['set'])} in {boot_seconds:.2f}s")

    print('timeline :')
    for phase in phases(boot):
        print(f"  +{phase['from']:5.2f}s  {phase['phase']:34} {phase['seconds']:5.2f}s  "
              f"{', '.join(phase['processes']) or '-'}")

    if trace_json:
        target = Path(trace_json)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps({'stop_seconds': stop_seconds,
                                      'boot_seconds': boot_seconds,
                                      'shutdown': phases(down),
                                      'phases': phases(boot)}, indent=2), 'utf-8')
        print(f'written  : {trace_json}')
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--restart', action='store_true',
                        help='stop and start Steam once, measuring both')
    parser.add_argument('--seconds', type=float, default=6.0,
                        help='observation window without --restart')
    parser.add_argument('--json', type=Path, help='write the measured phases here')
    args = parser.parse_args()
    return restart(args.json) if args.restart else observe(args.seconds)


if __name__ == '__main__':
    sys.exit(main())
