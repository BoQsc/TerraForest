#!/usr/bin/env python3
"""Windowed front end: the approval and the same staged bar, without a console.

Launched by steam/install_to_steam.pyw and steam/uninstall_from_steam.pyw (pythonw), so
nothing appears in a command prompt. One Tk window explains that TerraForest is added as
a non-Steam game and that Steam must be restarted, then shows the progress bar the
console build draws: same stage weights, same measured drift, 99 before 100.

When Tk is unavailable the launcher falls back to the headless tool, whose output goes to
steam/logs/gui.log.
"""
from pathlib import Path
import importlib.util
import queue
import sys
import threading

STEAM = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import steam_progress  # noqa: E402
import steam_confirm  # noqa: E402

LOG = STEAM/'logs'/'gui.log'
TITLES = {'install_to_steam': 'Installing TerraForest into Steam',
          'uninstall_from_steam': 'Removing TerraForest from Steam'}


class Sink:
    """Stand-in for stdout under pythonw, where sys.stdout is None."""

    def __init__(self, path=LOG):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.handle = self.path.open('a', encoding='utf-8', buffering=1)

    def write(self, text):
        self.handle.write(text)
        return len(text)

    def flush(self):
        self.handle.flush()

    def isatty(self):
        return False


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
    def cancel(self):
        self.code = 3
        self.root.destroy()

    def approve(self):
        for widget in (self.go_button, self.cancel_button):
            widget.state(['disabled'])
        self.stage.configure(text='Preparing...')
        self.run_tool()

    def run_tool(self):
        steam_tool = getattr(self.module, 'steam_tool', None)
        if steam_tool is not None:
            steam_tool.PROGRESS_FACTORY = lambda: GuiProgress(self.queue.put)
            steam_tool.CONFIRM = None  # approved by this window
        threading.Thread(target=self.work, daemon=True).start()
        self.root.after(50, self.pump)

    def work(self):
        sys.argv = [self.module.__name__] + self.argv
        try:
            code = self.module.main()
        except SystemExit as exc:
            code = exc.code if isinstance(exc.code, int) else 1
        except Exception as exc:  # noqa: BLE001 - reported in the window
            self.queue.put(('error', f'{type(exc).__name__}: {exc}'))
            code = 2
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
        self.cancel_button.grid_remove()
        self.go_button.configure(text='Close', command=self.root.destroy,
                                 state='normal')
        self.root.bind('<Return>', lambda event: self.root.destroy())

    def start(self):
        self.build()
        self.root.mainloop()
        return self.code


def load_tool(name):
    """Import steam/<name>.py as a module, so its main() can be driven here."""
    path = STEAM/f'{name}.py'
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f'{path}: cannot be imported')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def launch(tool_name, argv=None):
    """Run a tool in the window; without Tk, fall back to the headless tool."""
    argv = list(sys.argv[1:] if argv is None else argv)
    if sys.stdout is None or sys.stderr is None:
        sink = Sink()
        sys.stdout = sys.stdout or sink
        sys.stderr = sys.stderr or sink
    module = load_tool(tool_name)
    title = TITLES.get(tool_name, 'TerraForest')
    try:
        return App(module, argv, title).start()
    except Exception:  # noqa: BLE001 - no display: run headless, output in the log
        sys.argv = [tool_name] + argv
        try:
            return module.main()
        except SystemExit as exc:
            return exc.code if isinstance(exc.code, int) else 1


if __name__ == '__main__':
    print(__doc__.strip())
    print('launch it through steam/install_to_steam.pyw or steam/uninstall_from_steam.pyw')
