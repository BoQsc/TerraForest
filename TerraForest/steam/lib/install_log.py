#!/usr/bin/env python3
"""One diagnostic log for dependencies, console/windowed runs and their results.

Original AI-assisted maintenance for TerraForest. Existing log history is retained;
legacy gui.log/history.tsv content is absorbed into install.log once.
"""
from contextlib import nullcontext
from pathlib import Path
import datetime
import hashlib
import sys
import time
import traceback

LOG_DIR = Path(__file__).resolve().parent.parent/'logs'
DEFAULT_LOG = LOG_DIR/'install.log'
MARKER = '=== TerraForest Steam run ==='
CURRENT = None


class NullStream:
    def write(self, text):
        return len(text)

    def flush(self):
        pass

    def isatty(self):
        return False


def warn(message):
    if CURRENT is not None:
        CURRENT.warn(message)


def note(message):
    if CURRENT is not None:
        CURRENT.note(message)


def latest_text(path=None):
    if CURRENT is not None and not CURRENT.enabled:
        raise OSError('Logging is disabled for this run')
    path = Path(path) if path else (CURRENT.path if CURRENT is not None else DEFAULT_LOG)
    text = path.read_text('utf-8', errors='replace')
    return MARKER + text.rsplit(MARKER, 1)[1] if MARKER in text else text


class Tee:
    def __init__(self, stream, handle):
        self.stream = stream or NullStream()
        self.handle = handle

    def write(self, text):
        self.stream.write(text)
        self.handle.write(text)
        self.handle.flush()
        return len(text)

    def flush(self):
        self.stream.flush()
        self.handle.flush()

    def isatty(self):
        return bool(getattr(self.stream, 'isatty', lambda: False)())


class Run:
    def __init__(self, tool, argv, path=None, enabled=True, stream=None, clock=time.time):
        self.tool = tool
        self.argv = list(argv)
        self.path = Path(path) if path else DEFAULT_LOG
        self.enabled = enabled
        self.stream = stream
        self.clock = clock
        self.started = self.clock()
        self.warnings = 0
        self.code = 0
        self.handle = None
        self._saved = None

    def _line(self, level, message):
        if self.handle is not None:
            stamp = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
            self.handle.write(f'{stamp}  {level:5}  {message}\n')
            self.handle.flush()

    def warn(self, message):
        self.warnings += 1
        self._line('WARN', message)

    def note(self, message):
        self._line('INFO', message)

    def _absorb_legacy(self):
        if self.path != DEFAULT_LOG:
            return
        for name in ('gui.log', 'history.tsv'):
            legacy = self.path.parent/name
            if legacy.is_file():
                self.handle.write(f'\n--- Preserved legacy {name} ---\n')
                self.handle.write(legacy.read_text('utf-8', errors='replace'))
                self.handle.write('\n--- End legacy log ---\n')
                self.handle.flush()
                try:
                    legacy.unlink()
                except OSError as exc:
                    self.warn(f'Legacy content preserved, but could not remove {legacy}: {exc}')

    def __enter__(self):
        global CURRENT
        self._saved = sys.stdout, sys.stderr
        if self.enabled:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.handle = self.path.open('a', encoding='utf-8')
            self._absorb_legacy()
            self.handle.write('\n' + MARKER + '\n')
            self._line('START', f'{self.tool} {" ".join(self.argv)}'.strip())
            self._line('INFO', f'Python {sys.version.split()[0]} | {sys.executable}')
            self._line('INFO', f'Working directory: {Path.cwd()}')
            installer = Path(__file__).with_name('install_to_steam.py')
            if installer.is_file():
                self._line('INFO', f'Installer SHA256: {hashlib.sha256(installer.read_bytes()).hexdigest()}')
            sys.stdout = Tee(self.stream if self.stream is not None else sys.stdout, self.handle)
            sys.stderr = Tee(sys.stderr, self.handle)
            CURRENT = self
            print(f'log      : {self.path.resolve()}')
        else:
            sys.stdout = sys.stdout or NullStream()
            sys.stderr = sys.stderr or NullStream()
            CURRENT = self
        return self

    def __exit__(self, exc_type, exc, tb):
        global CURRENT
        if not self.enabled:
            sys.stdout, sys.stderr = self._saved
            CURRENT = None
            return False
        try:
            if exc is not None:
                if isinstance(exc, SystemExit):
                    self.code = exc.code if isinstance(exc.code, int) else (0 if exc.code is None else 1)
                else:
                    self.code = 1
                if self.code:
                    self._line('ERROR', f'{exc_type.__name__}: {exc}')
                    if not isinstance(exc, SystemExit):
                        traceback.print_exception(exc_type, exc, tb, file=self.handle)
            seconds = round(self.clock() - self.started, 1)
            state = 'incomplete' if self.code else ('warnings' if self.warnings else 'success')
            self._line('END', f'{self.tool} code={self.code} seconds={seconds} '
                             f'warnings={self.warnings} result={state}')
        finally:
            sys.stdout, sys.stderr = self._saved
            CURRENT = None
            self.handle.close()
            self.handle = None
        return False


def run(tool, argv, path=None, enabled=True):
    # Windowed launch owns the outer session so bootstrap/import failures and the
    # worker share the same stream and summary; do not tee the same output twice.
    if CURRENT is not None:
        return nullcontext(CURRENT)
    return Run(tool, argv, path, enabled)
