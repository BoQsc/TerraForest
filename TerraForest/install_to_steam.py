# SPDX-License-Identifier: 0BSD
"""One command that gets TerraForest into Steam as a playable entry.

1. copies the source Godot executable to `TerraForest.exe` (skipped when it is
   already there, unless `--force`),
2. stamps the app icon into that copy's PE resources (`tools/app_icon`),
3. registers the copy as a Steam non-Steam shortcut (`add_steam_shortcut.py`),
   which stops Steam, writes `shortcuts.vdf` and starts Steam again.

Usage:
    python install_to_steam.py                # copy if needed, icon, add, restart
    python install_to_steam.py --force        # re-copy the source first
    python install_to_steam.py --dry-run      # report only, touch nothing
    python install_to_steam.py --no-restart   # leave Steam stopped after the write
"""
from pathlib import Path
import argparse
import importlib.util
import shutil
import sys

ROOT = Path(__file__).resolve().parent
TARGET = ROOT/'TerraForest.exe'
ICON = ROOT/'tools'/'app_icon'/'terraforest.ico'
GODOT_RELATIVE = Path('steamapps')/'common'/'Godot Engine'/'Godot Engine.exe'


def load(name, path):
    """Import a sibling tool by path, so this script owns no duplicated logic."""
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f'{path}: cannot be imported')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


app_icon = load('set_app_icon', ROOT/'tools'/'app_icon'/'set_app_icon.py')
steam_tool = load('add_steam_shortcut', ROOT/'add_steam_shortcut.py')


def godot_sources():
    """Candidate source executables: the exported build first, then Godot itself."""
    found = [ROOT/'dist'/'TerraForest.exe']
    for steam in steam_tool.steam_roots():
        found.append(steam/GODOT_RELATIVE)
        folders = steam/'steamapps'/'libraryfolders.vdf'
        if not folders.is_file():
            continue
        text = folders.read_text('utf-8', 'replace')
        for line in text.splitlines():
            if '"path"' in line:
                path = line.split('"')
                if len(path) >= 4:
                    found.append(Path(path[3])/GODOT_RELATIVE)
    return [p for p in found if p.is_file()]


def prepare(source, force, dry_run):
    """Copy the source executable to TerraForest.exe when needed."""
    if TARGET.exists() and not force:
        print(f'copy     : kept {TARGET.name} ({TARGET.stat().st_size:,} bytes); '
              'use --force to re-copy')
        return False
    if source is None:
        raise SystemExit(f'{TARGET.name} is missing and no source executable was found; '
                         'pass --source PATH')
    if dry_run:
        print(f'copy     : would copy {source} -> {TARGET.name}')
        return False
    shutil.copyfile(source, TARGET)
    print(f'copy     : {source} -> {TARGET.name} ({TARGET.stat().st_size:,} bytes)')
    return True


def stamp(dry_run):
    """Apply the icon and verify the resources, reusing the app_icon tool."""
    if not ICON.is_file():
        raise SystemExit(f'{ICON}: icon missing; run tools/app_icon/make_app_icon.py')
    if dry_run:
        problems, count, _ = app_icon.check(TARGET, ICON)
        state = 'already matches' if not problems else f'{len(problems)} problem(s)'
        print(f'icon     : would stamp {ICON.name} ({count} images); current copy {state}')
        return not problems
    payload, count, kept = app_icon.patch(TARGET, ICON)
    problems, _, _ = app_icon.check(TARGET, ICON)
    print(f'icon     : {count} images stamped, .rsrc {payload} bytes, '
          f'kept {len(kept)} other resource(s)')
    if problems:
        for problem in problems:
            print(f'           FAIL {problem}')
        return False
    return True


def register(dry_run, name, restart, force, steam, account, last_world=False):
    """Add the shortcut through the Steam tool; it owns the restart and the backup."""
    root = steam or next((p for p in steam_tool.steam_roots() if (p/'userdata').is_dir()), None)
    if root is None:
        raise SystemExit('Steam install not found; pass --steam PATH')
    if account:
        shortcut = root/'userdata'/account/'config'/'shortcuts.vdf'
        if not shortcut.is_file():
            raise SystemExit(f'no shortcuts.vdf for account {account}')
    else:
        shortcut = steam_tool.accounts(root)[0]
    code = steam_tool.add(shortcut, name, TARGET.resolve(), dry_run, restart, force,
                          launch_options())
    if code == 0 and last_world:
        # A second entry, because one Steam entry cannot express two command lines.
        code = steam_tool.add(shortcut, f'{name} Last World', TARGET.resolve(), dry_run,
                              restart, force, launch_options('--continue-last'))
    return code


def launch_options(suffix=''):
    """The editor binary needs --path, or Steam opens the project manager instead."""
    return f'--path "{ROOT}"' + (f' {suffix}' if suffix else '')


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--source', type=Path,
                        help='executable to copy (default: dist build, else the Godot editor)')
    parser.add_argument('--name', default=steam_tool.DEFAULT_NAME, help='Steam library name')
    parser.add_argument('--force', action='store_true', help='re-copy over TerraForest.exe')
    parser.add_argument('--dry-run', action='store_true', help='report without changing anything')
    parser.add_argument('--no-restart', action='store_true', help='leave Steam stopped')
    parser.add_argument('--last-world', action='store_true',
                        help='also register the "Last World" entry (--continue-last)')
    parser.add_argument('--steam', type=Path, help='Steam install directory')
    parser.add_argument('--account', help='Steam account id under userdata')
    args = parser.parse_args()

    source = args.source or next(iter(godot_sources()), None)
    print(f'source   : {source or "<none found>"}')
    prepare(source, args.force, args.dry_run)
    if not TARGET.is_file():
        raise SystemExit(f'{TARGET.name}: nothing to stamp; no source was copied')
    if not stamp(args.dry_run):
        raise SystemExit('icon stamping failed; the shortcut was not touched')
    code = register(args.dry_run, args.name, not args.no_restart, args.force,
                    args.steam, args.account, args.last_world)
    if code == 0:
        print('done     : TerraForest is prepared and registered')
    return code


if __name__ == '__main__':
    sys.exit(main())
