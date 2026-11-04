#!/usr/bin/env python3
"""Windowed front end: the approval and the same staged bar, without a console.

Launched by steam/install_to_steam.pyw and steam/uninstall_from_steam.pyw (pythonw), so
nothing appears in a command prompt. One Tk window explains that TerraForest is added as
a non-Steam game and that Steam must be restarted, then shows the progress bar the
console build draws: same stage weights, same measured drift, 99 before 100.

When Tk is unavailable the launcher falls back to the headless tool, whose output goes to
steam/logs/install.log.
"""
from pathlib import Path
import importlib.util
import queue
import sys
import threading
import argparse
import traceback
import install_log

STEAM = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import steam_progress  # noqa: E402
import steam_confirm  # noqa: E402

LOG = install_log.DEFAULT_LOG
TITLES = {'install_to_steam': 'Installing TerraForest into Steam',
          'uninstall_from_steam': 'Removing TerraForest from Steam'}


class GuiProgress:
    """Console-bar percentages, posted as frames to the window."""

    def __init__(self, post, expected=None):
        self.post = post
        self.key = 'check'
        self.fraction = 0.0
        self.note = ''
        self.displayed = 0
        self.expected = expected or steam_progress.measured()

    def _frame(self, note=None):
        if note is not None:
            self.note = note
        percent = min(99, steam_progress.percent_at(self.key, self.fraction))
        self.displayed = max(self.displayed, percent)
        self.post(('frame', self.displayed, steam_progress.TITLES.get(self.key, ''), self.note))

    def stage(self, key, note=''):
        self.key, self.fraction, self.note = key, 0.0, note
        self._frame()

    def tick(self, fraction, note=None):
        self.fraction = max(0.0, min(1.0, fraction))
        self._frame(note)

    def drift(self, elapsed, note=None):
        self.tick(steam_progress.drift_fraction(elapsed, self.expected.get(self.key, 1.0)), note)

    def finish(self, note=''):
        self.note = note or self.note
        self.post(('frame', 99, self.note, self.note))
        self.post(('frame', 100, self.note, self.note))
        self.post(('done', self.note))

    def abort(self, note=''):
        self._frame(note)
        self.post(('abort', self.note))


class App:
    def __init__(self, module, argv, title):
        self.module = module
        self.argv = list(argv)
        self.title = title
        self.queue = queue.Queue()
        self.root = None
        self.code = 1
        self.error = ''

    # -- window ---------------------------------------------------------
    def build(self):
        import tkinter as tk
        from tkinter import ttk
        root = tk.Tk()
        root.title(self.title)
        root.resizable(False, False)
        frame = ttk.Frame(root, padding=16)
        frame.grid(row=0, column=0, sticky='nsew')
        ttk.Label(frame, text='Steam needs a restart',
                  font=('Segoe UI', 12, 'bold')).grid(row=0, column=0, sticky='w')
        ttk.Label(frame, text=steam_confirm.BODY, justify='left').grid(
            row=1, column=0, pady=(8, 0), sticky='w')
        self.bar = ttk.Progressbar(frame, length=420, maximum=100)
        self.bar.grid(row=2, column=0, pady=(16, 0), sticky='ew')
        self.percent = ttk.Label(frame, text='0%', font=('Segoe UI', 10, 'bold'))
        self.percent.grid(row=3, column=0, pady=(6, 0), sticky='w')
        self.stage = ttk.Label(frame, text='', foreground='#333')
        self.stage.grid(row=4, column=0, sticky='w')
        self.note = ttk.Label(frame, text='', foreground='#666', wraplength=420)
        self.note.grid(row=5, column=0, sticky='w')
        buttons = ttk.Frame(frame)
        buttons.grid(row=6, column=0, pady=(14, 0), sticky='e')
        ttk.Button(buttons, text='Copy log', command=self.copy_log).grid(row=0, column=2, padx=(8, 0))
        self.cancel_button = ttk.Button(buttons, text='Cancel', command=self.cancel)
        self.cancel_button.grid(row=0, column=0, padx=(0, 8))
        self.go_button = ttk.Button(buttons, text='Restart Steam and continue',
                                    command=self.approve)
        self.go_button.grid(row=0, column=1)
        self.go_button.focus_set()
        root.bind('<Escape>', lambda event: self.cancel())
        root.bind('<Return>', lambda event: self.approve())
        self.items = {'root': root, 'frame': frame, 'buttons': buttons}
        self.root = root
        return root

    # -- actions --------------------------------------------------------
    def copy_log(self):
        try:
            text = install_log.latest_text()
            self.root.clipboard_clear()
            self.root.clipboard_append(text)
            self.note.configure(text='Log copied. Paste it into the chat.')
        except OSError as exc:
            self.note.configure(text=f'Could not read the log: {exc}')

    def cancel(self):
        self.code = 3
        self.root.destroy()

    def approve(self):
        for widget in (self.go_button, self.cancel_button):
            widget.state(['disabled'])
        self.stage.configure(text='Preparing...')
        self.run_tool()

    def run_tool(self):
        engine = engine_of(self.module)
        if engine is not None:
            engine.PROGRESS_FACTORY = lambda: GuiProgress(self.queue.put)
            engine.CONFIRM = None  # approved by this window
        else:
            self.queue.put(('error', 'no engine module: the bar will stay at 0%'))
        threading.Thread(target=self.work, daemon=True).start()
        self.root.after(50, self.pump)

    def work(self):
        sys.argv = [self.module.__name__] + self.argv
        try:
            code = self.module.main()
        except SystemExit as exc:
            code = exc.code if isinstance(exc.code, int) else 1
            if not isinstance(exc.code, (int, type(None))):
                print(f'error    : {exc.code}', file=sys.stderr)
                self.queue.put(('error', str(exc.code)))
        except Exception as exc:  # noqa: BLE001 - reported in the window
            traceback.print_exc()
            self.queue.put(('error', f'{type(exc).__name__}: {exc}'))
            code = 2
        print(f'result   : {self.module.__name__} code={code}')
        self.queue.put(('exit', code))

    # -- rendering ------------------------------------------------------
    def pump(self):
        finished = False
        while True:
            try:
                message = self.queue.get_nowait()
            except queue.Empty:
                break
            kind = message[0]
            if kind == 'frame':
                _, percent, stage, note = message
                self.bar['value'] = percent
                self.percent.configure(text=f'{percent}%')
                self.stage.configure(text=stage)
                self.note.configure(text=note)
            elif kind == 'done':
                self.stage.configure(text='Finished')
                self.percent.configure(text='100%')
                self.bar['value'] = 100
            elif kind == 'abort':
                self.stage.configure(text=f'Stopped: {message[1]}')
            elif kind == 'error':
                self.error = message[1]
                self.stage.configure(text=f'Failed: {message[1]}')
            elif kind == 'exit':
                finished = True
                self.code = message[1]
        if finished:
            self.finish()
        else:
            self.root.after(50, self.pump)

    def finish(self):
        text = {0: 'Finished.', 3: 'Cancelled - nothing was written.'}.get(
            self.code, f'Stopped (code {self.code}).')
        self.stage.configure(text=text)
        if self.error:
            self.note.configure(text=self.error)
        self.cancel_button.grid_remove()
        self.go_button.configure(text='Close', command=self.root.destroy,
                                 state='normal')
        self.root.bind('<Return>', lambda event: self.root.destroy())

    def start(self):
        self.build()
        self.root.mainloop()
        return self.code


def load_tool(name):
    """Import the tool module, so its main() can be driven here.

    Console scripts live in steam/lib/; anything left beside the launchers in steam/
    is still found, so the lookup keeps working if a tool moves again.
    """
    path = next((folder/f'{name}.py' for folder in (STEAM/'lib', STEAM)
                 if (folder/f'{name}.py').is_file()), None)
    if path is None:
        raise SystemExit(f'{name}.py: not found in steam/lib or steam')
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f'{path}: cannot be imported')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def engine_of(module):
    """The engine instance the tool's own main() uses, or None.

    install_to_steam exposes it as `steam_tool`; uninstall_from_steam exposes an
    `add_tool()` that caches, so both paths configure the same object main() runs.
    """
    engine = getattr(module, 'steam_tool', None)
    if engine is not None:
        return engine
    provider = getattr(module, 'add_tool', None)
    return provider() if callable(provider) else None


def launch(tool_name, argv=None):
    """Run a tool in the window; without Tk, fall back to the headless tool."""
    argv = list(sys.argv[1:] if argv is None else argv)
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--log', type=Path)
    parser.add_argument('--no-log', action='store_true')
    settings, _ = parser.parse_known_args(argv)
    with install_log.run(tool_name, argv, settings.log, enabled=not settings.no_log) as run:
        if tool_name == 'install_to_steam':
            import ensure_deps
            ensure_deps.bootstrap()
        module = load_tool(tool_name)
        title = TITLES.get(tool_name, 'TerraForest')
        try:
            app = App(module, argv, title)
            app.build()
        except Exception as exc:  # no display: run the same tool headless
            print(f'window   : unavailable ({exc}); continuing without the window')
            sys.argv = [tool_name] + argv
            run.code = module.main()
        else:
            app.root.mainloop()
            run.code = app.code
        return run.code


if __name__ == '__main__':
    print(__doc__.strip())
    print('launch it through steam/install_to_steam.pyw or steam/uninstall_from_steam.pyw')
