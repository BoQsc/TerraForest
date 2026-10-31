#!/usr/bin/env python3
"""Staged progress bar for the Steam restart.

Percentages come from observed process state, not a timer: the stop stage counts how
many Steam processes are still alive, the start stage polls for steam.exe to return.
Stages without anything to observe (the file write) complete instantly.

It draws one updating line on a terminal and stays completely silent otherwise, so
piped output and tests keep their plain lines.

Usage:
    python steam/steam_progress.py --demo     # preview the stages, touches nothing
"""
import sys
import time

# (key, title, share of the whole bar). The shares are the weight of each stage;
# the bar shows how far through the sequence we are, not wall-clock time.
STAGES = (
    ('check', 'Checking Steam processes', 0.08),
    ('stop', 'Stopping Steam', 0.30),
    ('write', 'Writing shortcuts.vdf', 0.12),
    ('start', 'Starting Steam', 0.40),
    ('verify', 'Verifying the file', 0.10),
)
TITLES = {key: title for key, title, _ in STAGES}


class Progress:
    """One updating line on a terminal; nothing at all when not on one."""

    WIDTH = 24
    MAX_LINE = 118

    def __init__(self, stream=None, enabled=None):
        self.stream = stream if stream is not None else sys.stdout
        if enabled is None:
            enabled = bool(getattr(self.stream, 'isatty', lambda: False)())
        self.enabled = enabled
        self.key = None
        self.fraction = 0.0
        self.note = ''
        self._last_percent = None
        self._drawn = False

    def stage(self, key, note=''):
        """Enter a stage: the bar jumps to that stage's starting percent."""
        self.key, self.fraction, self.note = key, 0.0, note
        self._draw(force=True)

    def tick(self, fraction, note=None):
        """Report how far through the current stage we are, from observation."""
        self.fraction = max(0.0, min(1.0, fraction))
        if note is not None:
            self.note = note
        self._draw()

    def finish(self, note=''):
        """Whole sequence complete: the bar fills, whatever stage we are on."""
        self.key = STAGES[-1][0]
        self.note = note
        self.fraction = 1.0
        self._draw(force=True)
        self._end_line()

    def abort(self, note=''):
        """Stopped early: keep the real percent so the bar never claims success."""
        self.note = note
        self._draw(force=True)
        self._end_line()

    def _end_line(self):
        if self.enabled and self._drawn:
            self.stream.write('\n')
            self.stream.flush()

    def percent(self):
        done = 0.0
        for key, _, share in STAGES:
            if key == self.key:
                return int(round((done + share*self.fraction)*100))
            done += share
        return int(round(done*100))

    def render(self):
        percent = self.percent()
        filled = int(self.WIDTH*percent/100)
        bar = '#'*filled + '-'*(self.WIDTH-filled)
        line = f'[{bar}] {percent:3d}%  {TITLES.get(self.key, "")}'
        if self.note:
            line += f' · {self.note}'
        return line[:self.MAX_LINE]

    def _draw(self, force=False):
        if not self.enabled:
            return
        percent = self.percent()
        if not force and percent == self._last_percent:
            return
        self._last_percent = percent
        self.stream.write('\r' + self.render().ljust(self.MAX_LINE))
        self.stream.flush()
        self._drawn = True


def demo(seconds=0.9):
    """Walk the stages with plausible notes, so the display can be judged off-line."""
    # Forced on: the point of --demo is to show the frames even when piped.
    progress = Progress(enabled=True)
    print('progress : preview; a real run only animates on a terminal')
    plan = (('check', '2 processes: steam.exe, steamwebhelper.exe'),
            ('stop', None), ('write', None), ('start', None),
            ('verify', '2 entries'))
    for key, note in plan:
        progress.stage(key, note or '')
        for step in range(1, 6):
            time.sleep(seconds/5)
            progress.tick(step/5, note or f'step {step}/5')
    progress.finish('done')
    return 0


if __name__ == '__main__':
    sys.exit(demo() if '--demo' in sys.argv else print(__doc__.strip()) or 0)
