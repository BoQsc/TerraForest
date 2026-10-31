#!/usr/bin/env python3
"""Remove the Steam shortcuts that install_to_steam.py put in the library.

Uninstalling is its own entry point so nobody has to remember `--remove` on the
shared engine (`steam/steam_shortcuts.py`), and so the usual pair of entries (the
plain launch and the "last world" launch) can be dropped together in one pass,
with one Steam restart.

Both entries are removed by default. The executable is not touched, and neither
are the desktop shortcuts (see add_desktop_shortcuts.py for those).

`--artwork` also deletes the grid images install_to_steam.py copied, matching
them by each entry's app id.

Usage:
    python steam/uninstall_from_steam.py               # remove both entries
    python steam/uninstall_from_steam.py --artwork     # and their grid images
    python steam/uninstall_from_steam.py --dry-run     # report only
    python steam/uninstall_from_steam.py --list        # show what Steam has now
    python steam/uninstall_from_steam.py --name TerraForest
"""
from pathlib import Path
import argparse
import importlib.util
import json
import sys

# This file lives in steam/; tools/ and the play build are one level up.
ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT/'steam'/'manifest.json'
MAIN_NAME = 'TerraForest'
DEFAULT_NAMES = (MAIN_NAME, f'{MAIN_NAME} Last World')


def add_tool():
    """Import steam/steam_shortcuts.py, which owns shortcuts.vdf and the restart."""
    path = ROOT/'steam'/'steam_shortcuts.py'
    spec = importlib.util.spec_from_file_location('add_steam_shortcut', path)
    if spec is None or spec.loader is None:
        raise SystemExit(f'{path}: cannot be imported')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def target_names(requested=None):
    """Entries to remove: what was asked for, else both the plain and last-world ones."""
    return tuple(requested) if requested else DEFAULT_NAMES


def desktop_tool():
    """Import add_desktop_shortcuts.py, which owns the .lnk files and their names."""
    path = ROOT/'steam'/'add_desktop_shortcuts.py'
    spec = importlib.util.spec_from_file_location('add_desktop_shortcuts', path)
    if spec is None or spec.loader is None:
        raise SystemExit(f'{path}: cannot be imported')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def remove_artwork(shortcut, names, exe, dry_run, tool):
    """Delete the grid images install_to_steam.py copied, named by each entry's app id."""
    mapping = json.loads(MANIFEST.read_text('utf-8'))['artwork']
    grid = shortcut.parent/'grid'
    if not grid.is_dir():
        print('artwork  : no grid folder; nothing to remove')
        return 0
    removed = 0
    for name in names:
        appid = tool.shortcut_appid(str(exe), name)
        for pattern in mapping.values():
            target = grid/pattern.replace('{appid}', str(appid))
            if not target.is_file():
                continue
            print(f'artwork  : remove {target.name}')
            if not dry_run:
                target.unlink()
            removed += 1
    print(f'artwork  : {removed} file(s) {"would be removed" if dry_run else "removed"}'
          f' from {grid}')
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--exe', type=Path,
                        help='executable the entries point at (default: the project build)')
    parser.add_argument('--name', action='append',
                        help='entry to remove; repeatable (default: both TerraForest entries)')
    parser.add_argument('--steam', type=Path, help='Steam install directory')
    parser.add_argument('--account', help='Steam account id under userdata')
    parser.add_argument('--list', action='store_true', help='list the entries and exit')
    parser.add_argument('--artwork', action='store_true',
                        help='also delete the grid images install_to_steam.py copied')
    parser.add_argument('--dry-run', action='store_true',
                        help='report without touching shortcuts.vdf or Steam')
    parser.add_argument('--no-restart', action='store_true',
                        help='stop Steam for the write but leave it stopped')
    parser.add_argument('--force', action='store_true',
                        help='stop Steam even if a game session looks active')
    parser.add_argument('--progress', choices=('auto', 'bar', 'plain', 'off'), default='auto',
                        help='restart display: auto (bar on a terminal), bar, plain, off')
    parser.add_argument('--desktop', action=argparse.BooleanOptionalAction, default=True,
                        help='also delete the desktop shortcuts (default: yes; --no-desktop keeps them)')
    parser.add_argument('--desktop-folder', type=Path,
                        help='desktop folder to clean (default: the real desktop)')
    args = parser.parse_args()

    tool = add_tool()
    tool.PROGRESS_MODE = args.progress
    steam = args.steam or next((p for p in tool.steam_roots() if (p/'userdata').is_dir()), None)
    if steam is None:
        parser.error('Steam install not found; pass --steam PATH')
    if args.account:
        shortcut = steam/'userdata'/args.account/'config'/'shortcuts.vdf'
        if not shortcut.is_file():
            parser.error(f'no shortcuts.vdf for account {args.account}')
    else:
        accounts = tool.accounts(steam)
        if not accounts:
            parser.error(f'{steam}: no account with a shortcuts.vdf')
        shortcut = accounts[0]

    if args.list:
        _, _, entries = tool.load(shortcut)
        print(f'{shortcut}: {len(entries)} shortcut(s)')
        grid = shortcut.parent/'grid'
        mapping = json.loads(MANIFEST.read_text('utf-8'))['artwork']
        for index, fields in sorted(entries.items(), key=lambda item: int(item[0])):
            appid = fields.get('appid')
            tag = f'[{appid & 0xFFFFFFFF}]' if isinstance(appid, int) else '[no appid]'
            present = sum(1 for pattern in mapping.values()
                          if (grid/pattern.replace('{appid}', str(appid & 0xFFFFFFFF))).is_file())
            print(f'  {index}: {fields.get("AppName")}  {fields.get("Exe")}  {tag}'
                  f'  artwork {present}/{len(mapping)}')
        return 0

    exe = args.exe or next((p for p in tool.CANDIDATE_EXES if p.exists()), None)
    if exe is None or not exe.exists():
        parser.error('executable not found; pass --exe PATH')
    exe = exe.resolve()

    names = target_names(args.name)
    print(f'file     : {shortcut}')
    print(f'exe      : {exe}')
    print(f'entries  : {", ".join(names)}')
    # The desktop links go as soon as the entry is out of shortcuts.vdf, before the
    # long wait for Steam to boot again, so nothing stale is left while it restarts.
    cleaned = {'desktop': False}

    def clean_desktop():
        if args.desktop and not cleaned['desktop']:
            cleaned['desktop'] = True
            desktop_tool().remove_shortcuts(args.desktop_folder, args.dry_run)

    code = tool.remove_all(shortcut, names, exe, args.dry_run,
                           not args.no_restart, args.force, after_write=clean_desktop)
    if code == 0 and args.artwork:
        code = remove_artwork(shortcut, names, exe, args.dry_run, tool)
    if code == 0:
        # Dry runs and "nothing to remove" never reach the write, so clean here too.
        clean_desktop()
    return code


if __name__ == '__main__':
    sys.exit(main())
