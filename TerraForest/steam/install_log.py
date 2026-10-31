#!/usr/bin/env python3
"""Run log for the Steam install and uninstall tools.

Every run appends a header, everything the tool prints, a summary with the exit code,
duration and a count of warnings, and one compact row in history.tsv. Anything that
counts as "unstable" - an entry Steam dropped and we re-added, a missing desktop link,
a refused write - is logged as WARN, so a bad run is visible without reading all output.

Usage (from the tools themselves):
    with install_log.run('install_to_steam', sys.argv[1:]) as run:
        ...
        install_log.warn('Steam dropped the entry; re-added')
"""
from pathlib import Path
import datetime
import sys
import time

LOG_DIR = Path(__file__).resolve().parent/'logs'
DEFAULT_LOG = LOG_DIR/'install.log'
HISTORY = LOG_DIR/'history.tsv'
# Set by run(); the module level helpers below write through it.
CURRENT = None


def warn(message):
    """Record something that should not normally happen; makes the run unstable."""
    if CURRENT is not None:
        CURRENT.warn(message)


def note(message):
    if CURRENT is not None:
        CURRENT.note(message)


class Tee:
    """Mirror whatever the tool prints into the log file."""

    def __init__(self, stream, handle):
        self.stream = stream
        self.handle = handle

    def write(self, text):
        self.stream.write(text)
        if self.handle is not None:
            self.handle.write(text)
            self.handle.flush()
        return len(text)

    def flush(self):
        self.stream.flush()
        if self.handle is not None:
            self.handle.flush()

    def isatty(self):
        return bool(getattr(self.stream, 'isatty', lambda: False)())


class Run:
    def __init__(self, tool, argv, path=None, enabled=True, stream=None, clock=time.time):
        self.tool = tool
        self.argv = list(argv)
        self.path = Path(path) if path else DEFAULT_LOG
        self.enabled = enabled
        self.stream = stream if stream is not None else sys.stdout
        self.clock = clock
        self.started = self.clock()
        self.warnings = 0
        self.handle = None
        self._tee = None
        self._saved = None

    # -- logging --------------------------------------------------------
    def _line(self, level, message):
        if self.handle is None:
            return
        stamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        self.handle.write(f'{stamp}  {level:5}  {message}\n')
        self.handle.flush()

    def warn(self, message):
        self.warnings += 1
        self._line('WARN', message)

    def note(self, message):
        self._line('INFO', message)

    # -- lifecycle ------------------------------------------------------
    def __enter__(self):
        global CURRENT
        if self.enabled:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.handle = self.path.open('a', encoding='utf-8')
            self._line('START', f'{self.tool} {" ".join(self.argv)}'.strip())
            self._saved = sys.stdout
            self._tee = Tee(self.stream, self.handle)
            sys.stdout = self._tee
            CURRENT = self
        return self

    def __exit__(self, exc_type, exc, traceback):
        global CURRENT
        if not self.enabled:
            return False
        seconds = round(self.clock() - self.started, 1)
        if exc is not None:
            code = 1
            self._line('ERROR', f'{exc_type.__name__}: {exc}')
        else:
            code = 0
        state = 'UNSTABLE' if self.warnings or exc is not None else 'clean'
        self._line('END', f'{self.tool} code={code} seconds={seconds} '
                          f'warnings={self.warnings} result={state}')
        with HISTORY.open('a', encoding='utf-8') as history:
            if history.tell() == 0:
                history.write('when\ttool\tcode\tseconds\twarnings\tresult\targs\n')
            history.write(f'{datetime.datetime.now():%Y-%m-%d %H:%M:%S}\t{self.tool}\t{code}\t'
                          f'{seconds}\t{self.warnings}\t{state}\t{" ".join(self.argv)}\n')
        sys.stdout = self._saved
        self.handle.close()
        self.handle = None
        CURRENT = None
        return False


def run(tool, argv, path=None, enabled=True):
    return Run(tool, argv, path, enabled)
