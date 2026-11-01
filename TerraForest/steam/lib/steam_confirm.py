#!/usr/bin/env python3
"""A small approval dialog for the Steam restart.

Before Steam is stopped, the tools ask once in a tiny Tk window: TerraForest is being
added as a **non-Steam game** shortcut, and Steam must be closed and reopened for it to
appear. The dialog is skipped when nobody is there to answer (piped output, --yes), so
scripted runs keep working.

Usage:
    python steam/lib/steam_confirm.py --demo    # show the dialog and print the answer
"""
import sys

TITLE = 'TerraForest - Steam restart'
HEADING = 'Steam needs a restart'
BODY = (
    'TerraForest will be added to your Steam library as a '
    'non-Steam game shortcut.\n\n'
    'It is not a real Steam app: Steam keeps these shortcuts in shortcuts.vdf, and it\n'
    'only reads that file while closed - so Steam has to be closed and reopened now.\n\n'
    'Nothing else in your library changes. Steam takes about 25 seconds to come back.'
)


def available():
    """True when a Tk window can actually be created here."""
    try:
        import tkinter
        root = tkinter.Tk()
        root.destroy()
        return True
    except Exception:
        return False


def should_confirm(args, interactive=None):
    """Decide from the command line whether the dialog is appropriate."""
    if getattr(args, 'yes', False) or getattr(args, 'no_confirm', False):
        return False
    if getattr(args, 'confirm', False):
        return True
    if interactive is None:
        try:
            interactive = sys.stdin.isatty()
        except (AttributeError, ValueError):
            interactive = False
    return bool(interactive) and available()


def ask(detail='', ask_impl=None):
    """Ask for approval; anything unexpected falls back to proceeding."""
    if ask_impl is not None:
        return bool(ask_impl(detail))
    try:
        import tkinter as tk
        from tkinter import ttk
    except Exception:
        return True
    try:
        root = tk.Tk()
    except Exception:
        return True
    root.title(TITLE)
    root.resizable(False, False)
    frame = ttk.Frame(root, padding=16)
    frame.grid(row=0, column=0, sticky='nsew')
    answer = {'ok': False}

    ttk.Label(frame, text=HEADING, font=('Segoe UI', 12, 'bold')).grid(
        row=0, column=0, sticky='w')
    ttk.Label(frame, text=BODY, justify='left').grid(row=1, column=0, pady=(8, 0), sticky='w')
    if detail:
        ttk.Label(frame, text=detail, justify='left', foreground='#444').grid(
            row=2, column=0, pady=(8, 0), sticky='w')
    buttons = ttk.Frame(frame)
    buttons.grid(row=3, column=0, pady=(14, 0), sticky='e')

    def finish(ok):
        answer['ok'] = ok
        root.destroy()

    ttk.Button(buttons, text='Cancel', command=lambda: finish(False)).grid(
        row=0, column=0, padx=(0, 8))
    accept = ttk.Button(buttons, text='Restart Steam and continue', command=lambda: finish(True))
    accept.grid(row=0, column=1)
    accept.focus_set()
    root.bind('<Escape>', lambda event: finish(False))
    root.bind('<Return>', lambda event: finish(True))
    root.update_idletasks()
    root.wait_window()
    return answer['ok']


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if '--demo' not in argv:
        print(__doc__.strip())
        return 0
    print('available:', available())
    print('approved :', ask('This run adds: TerraForest, TerraForest Last World'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
