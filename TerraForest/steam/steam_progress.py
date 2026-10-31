#!/usr/bin/env python3
"""Staged progress bar for the Steam restart.

Percentages follow observed process state, and the motion between observations is
shaped by measurement: each stage has an expected duration (from steam/traces), the
bar drifts toward that stage's end asymptotically instead of freezing, big jumps are
interpolated over a few frames, and the bar holds just below 100% for a moment so the
last steps are actually visible.

It draws one updating line on a terminal, prints plain lines on request, and stays
completely silent otherwise.

Usage:
    python steam/steam_progress.py --demo                 # animated preview
    python steam/steam_progress.py --demo --mode plain    # the same frames, as lines
"""
import math
import sys
import time

# (key, title, share of the whole bar). Shares are weights; the bar shows progress
# through the sequence, not wall-clock time.
STAGES = (
    # Shares follow measured durations: the window wait (24 s of a ~29 s run) is
    # nearly all of the wall clock, so it owns most of the bar. Giving it 40% made
    # the bar crawl through the longest phase.
    ('check', 'Checking Steam processes', 0.05),
    ('stop', 'Stopping Steam', 0.15),
    ('write', 'Writing shortcuts.vdf', 0.05),
    ('start', 'Starting Steam', 0.70),
    ('verify', 'Verifying the file', 0.05),
)
TITLES = {key: title for key, title, _ in STAGES}
MODES = ('auto', 'bar', 'plain', 'off')

# Measured fallbacks (seconds) when steam/traces/steam-boot.json is not there.
EXPECTED = {'check': 0.3, 'stop': 4.0, 'write': 0.3, 'start': 25.0, 'verify': 0.4}


def measured(defaults=None):
    """Expected stage durations, preferring what steam_trace.py measured."""
    import json
    from pathlib import Path
    expected = dict(defaults or EXPECTED)
    trace = Path(__file__).resolve().parent/'traces'/'steam-boot.json'
    try:
        data = json.loads(trace.read_text('utf-8'))
        expected['stop'] = float(data.get('stop_seconds') or expected['stop'])
        # The window is what the bar waits for, so prefer its measured time: the
        # process settle ("boot_seconds") happens long before Steam is usable.
        expected['start'] = float(data.get('window_seconds')
                                  or data.get('boot_seconds') or expected['start'])
    except (OSError, ValueError, TypeError):
        pass
    return expected


def drift_fraction(elapsed, expected):
    """How far through a stage we plausibly are after `elapsed` seconds.

    Linear against the measured duration, capped at 0.95: the bar sweeps the stage
    at the pace the stage actually takes, and only the real event finishes it.
    """
    if expected <= 0:
        return 1.0
    return min(0.95, max(0.0, elapsed)/expected)


class Progress:
    WIDTH = 24
    MAX_LINE = 118
    SMOOTH = 6          # points per frame; bigger jumps are interpolated
    FRAME = 0.05        # seconds per interpolated frame
    DWELL = 0.15        # hold at 99% before showing 100%

    def __init__(self, stream=None, enabled=None, mode='auto'):
        self.stream = stream if stream is not None else sys.stdout
        if mode not in MODES:
            raise SystemExit(f'{mode}: progress mode must be one of {", ".join(MODES)}')
        on_terminal = bool(getattr(self.stream, 'isatty', lambda: False)())
        extra_frames = False
        if mode == 'auto':
            mode = 'bar' if on_terminal else 'off'
        if mode == 'plain':
            # Plain lines are for logs: no sleeping between frames.
            extra_frames = True
        self.mode = mode
        self.enabled = mode != 'off' if enabled is None else enabled
        self.key = None
        self.fraction = 0.0
        self.note = ''
        self.displayed = 0
        self._last_bucket = None
        self._drawn = False
        self._finishing = False
        self.expected = measured()
        self.animate = not extra_frames

    # -- stages ---------------------------------------------------------
    def stage(self, key, note=''):
        self.key, self.fraction, self.note = key, 0.0, note
        self._draw(force=True)

    def tick(self, fraction, note=None):
        self.fraction = max(0.0, min(1.0, fraction))
        if note is not None:
            self.note = note
        self._draw()

    def drift(self, elapsed, note=None):
        """Advance the current stage by measured time rather than frozen at a step."""
        expected = self.expected.get(self.key, 1.0)
        self.tick(drift_fraction(elapsed, expected), note)

    def finish(self, note=''):
        self.note = note
        self.key = STAGES[-1][0]
        if self.displayed < 99:
            self._animate_to(99)
            if self.animate:
                time.sleep(self.DWELL)
        self._finishing = True
        self.fraction = 1.0
        self._animate_to(100, force=True)
        self._end_line()

    def abort(self, note=''):
        self.note = note
        self._draw(force=True)
        self._end_line()

    # -- arithmetic -----------------------------------------------------
    def percent_for(self, key, fraction):
        done = 0.0
        for name, _, share in STAGES:
            if name == key:
                return int(round((done + share*fraction)*100))
            done += share
        return int(round(done*100))

    def percent(self):
        return self.percent_for(self.key, self.fraction)

    def render(self, percent=None):
        value = self.percent() if percent is None else percent
        filled = int(self.WIDTH*value/100)
        bar = '#'*filled + '-'*(self.WIDTH-filled)
        line = f'[{bar}] {value:3d}%  {TITLES.get(self.key, "")}'
        if self.note:
            line += f' · {self.note}'
        return line[:self.MAX_LINE]

    # -- drawing --------------------------------------------------------
    def _write(self, percent):
        # Never go backwards, whatever a stage reset or a late tick computes.
        percent = max(percent, self.displayed)
        if self.mode == 'plain':
            self.stream.write(self.render(percent) + '\n')
        else:
            self.stream.write('\r' + self.render(percent).ljust(self.MAX_LINE))
        self.stream.flush()
        self._drawn = True
        self.displayed = percent

    def _animate_to(self, target, force=False):
        """Walk from the displayed value to target, a few points per frame."""
        if not self.enabled:
            return
        if force and self.displayed == target:
            self._write(target)
            return
        if self.mode == 'plain':
            # One line per 10% bucket, plus the exact target when forced.
            bucket = target//10
            # The last tenth is printed explicitly (99 then 100) so the top end is
            # never swallowed by the bucket that 90% already used.
            if force or target >= 99 or bucket != self._last_bucket:
                self._last_bucket = bucket
                self._write(target)
            return
        while self.displayed < target:
            step = min(self.SMOOTH, target - self.displayed)
            if step <= 0:
                break
            self._write(self.displayed + step)
            if self.animate and self.displayed < target:
                time.sleep(self.FRAME)
        if force and self.displayed < target:
            self._write(target)

    def _draw(self, force=False):
        if not self.enabled:
            return
        # A stage tick may approach its end but never draw 100: only finish() does,
        # so the last percent is always a deliberate, visible step.
        target = self.percent() if self._finishing else min(99, self.percent())
        if target == self.displayed and not force:
            return
        self._animate_to(target, force=force)

    def _end_line(self):
        if self.enabled and self._drawn:
            if self.mode != 'plain':
                self.stream.write('\n')
                self.stream.flush()


def demo(seconds=0.35, mode='bar'):
    """Walk the stages with plausible notes, so the display can be judged off-line."""
    progress = Progress(mode=mode)
    if not progress.enabled:
        print('progress : off (pass --mode plain to print lines instead of frames)')
        return 0
    print(f'progress : preview ({progress.mode})')
    plan = (('check', '2 processes: steam.exe, steamwebhelper.exe'),
            ('stop', None), ('write', None), ('start', None),
            ('verify', '2 entries'))
    for key, note in plan:
        progress.stage(key, note or '')
        started = time.time()
        for _ in range(5):
            time.sleep(seconds/5)
            progress.drift(time.time()-started, note or None)
    progress.finish('done')
    return 0


if __name__ == '__main__':
    if '--demo' in sys.argv:
        requested = 'bar'
        if '--mode' in sys.argv:
            requested = sys.argv[sys.argv.index('--mode')+1]
        sys.exit(demo(mode=requested))
    print(__doc__.strip())
