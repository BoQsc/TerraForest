# SPDX-License-Identifier: 0BSD
"""One command that gets TerraForest into Steam as a playable entry.

1. copies the source Godot executable to `TerraForest.exe` (skipped when it is
   already there, unless `--force`),
2. stamps the app icon into that copy's PE resources (`steam/app_icon`),
3. registers the copy as a Steam non-Steam shortcut (`steam/steam_shortcuts.py`),
   which stops Steam, writes `shortcuts.vdf` and starts Steam again.

Usage:
    python steam/lib/install_to_steam.py                # copy if needed, icon, add, restart
    python steam/lib/install_to_steam.py --force        # re-copy the source first
    python steam/lib/install_to_steam.py --dry-run      # report only, touch nothing
    python steam/lib/install_to_steam.py --no-restart   # leave Steam stopped after the write
"""
from pathlib import Path
import argparse
import ctypes
import datetime
import hashlib
import importlib.util
import json
import shutil
import struct
import sys

# This file lives in steam/lib/; the play build is two levels up.
ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT/'TerraForest.exe'
ICON = ROOT/'steam'/'app_icon'/'terraforest.ico'
MANIFEST = ROOT/'steam'/'manifest.json'
ARTWORK = ROOT/'steam'/'artwork'
BROWSER_SCENE = 'res://demo/worlds.tscn'
SHCNE_UPDATEITEM = 0x00002000
SHCNF_PATHW = 0x0005


def load(name, path):
    """Import a sibling tool by path, so this script owns no duplicated logic."""
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f'{path}: cannot be imported')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


app_icon = load('set_app_icon', ROOT/'steam'/'app_icon'/'set_app_icon.py')
# The importable modules live in steam/lib/; the entry points stay in steam/.
steam_tool = load('steam_shortcuts', ROOT/'steam'/'lib'/'steam_shortcuts.py')
import install_log as log_tool
confirm_tool = load('steam_confirm', ROOT/'steam'/'lib'/'steam_confirm.py')
source_tool = load('exe_source', ROOT/'steam'/'lib'/'exe_source.py')


def godot_sources(steam=None):
    """Candidate source executables: the exported build first, then Godot itself."""
    roots = ([steam] if steam else []) + steam_tool.steam_roots()
    found = source_tool.source_candidates(ROOT, roots)
    return [p for p in found if p.is_file()]


def prepare(source, force, dry_run):
    """Copy the source executable to TerraForest.exe when needed."""
    if TARGET.is_file() and not force:
        print(f'copy     : kept {TARGET.name} ({TARGET.stat().st_size:,} bytes); '
              'use --force to re-copy')
        return False
    if source is None:
        raise SystemExit('No source executable was found. Install Godot Engine in Steam '
                         '(any library), set GODOT_EXE to your Godot executable, or pass '
                         '--source "C:\\path\\to\\Godot.exe". '
                         'Steam has not been changed.')
    if not source.is_file():
        raise SystemExit(f'{source}: source executable does not exist. '
                         'Choose an existing Godot executable with --source or GODOT_EXE. '
                         'Steam has not been changed.')
    if source.resolve() == TARGET.resolve():
        print(f'copy     : source is already {TARGET.name}; no copy needed')
        return False
    if dry_run:
        print(f'copy     : would copy {source} -> {TARGET.name}')
        return False
    shutil.copyfile(source, TARGET)
    print(f'copy     : {source} -> {TARGET.name} ({TARGET.stat().st_size:,} bytes)')
    return True


def stamp(dry_run, executable=None):
    """Apply the icon and verify the resources, reusing the app_icon tool."""
    if not ICON.is_file():
        raise SystemExit(f'{ICON}: icon missing; run steam/app_icon/make_app_icon.py')
    if dry_run:
        inspected = executable or TARGET
        problems, count, _ = app_icon.check(inspected, ICON)
        state = 'already matches' if not problems else f'{len(problems)} problem(s)'
        print(f'icon     : would stamp {ICON.name} ({count} images); {inspected.name} {state}')
        # A different source icon is precisely what stamping will replace.
        return True
    payload, count, kept = app_icon.patch(TARGET, ICON)
    problems, _, _ = app_icon.check(TARGET, ICON)
    # The patch keeps the file length, so Explorer keeps any icon it cached for this
    # path while the copy was still incomplete. Re-read it after stamping.
    refresh_icon(TARGET)
    print(f'icon     : {count} images stamped, .rsrc {payload} bytes, '
          f'kept {len(kept)} other resource(s)')
    if problems:
        for problem in problems:
            print(f'           FAIL {problem}')
        return False
    return True


def refresh_icon(path):
    """Tell the shell an executable's icon changed; raw image patches do not."""
    shell32 = ctypes.WinDLL('shell32')
    shell32.SHChangeNotify.argtypes = [ctypes.c_long, ctypes.c_uint, ctypes.c_void_p,
                                       ctypes.c_void_p]
    shell32.SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW, ctypes.c_wchar_p(str(path)), None)


def wanted_entries(name, last_world=True, desktop=None):
    """Both entries; each records the desktop link Steam removes with the entry."""
    tags = tuple(json.loads(MANIFEST.read_text('utf-8')).get('tags', ()))
    names = [(name, '')] + ([(f'{name} Last World', '--continue-last')] if last_world else [])
    links = [desktop/f'{entry_name}.lnk' if desktop else None for entry_name, _ in names]
    return [steam_tool.shortcut_fields(entry_name, TARGET.resolve(), launch_options(suffix),
                                       str(ICON), tags, str(link) if link else '')
            for (entry_name, suffix), link in zip(names, links)]


def register(dry_run, name, restart, force, steam, account, last_world=True, shortcut=None,
             artwork=False, desktop=None):
    """Add the shortcut through the Steam tool; it owns the restart and the backup."""
    shortcut = shortcut or shortcut_file(steam, account)
    wanted = wanted_entries(name, last_world, desktop)
    apply_artwork = (lambda: install_artwork(shortcut, [entry['AppName'] for entry in wanted],
                                             dry_run)) if artwork else None
    # Steam caches custom images. Even an artwork-only repair must reopen Steam
    # after the files are installed, including an already-present but stale grid.
    code = steam_tool.upsert_all(shortcut, wanted, dry_run, restart, force,
                                 after_write=apply_artwork, refresh=artwork)
    if code == 0 and artwork and dry_run:
        install_artwork(shortcut, [entry['AppName'] for entry in wanted], True)
    return code


def shortcut_file(steam, account):
    """The shortcuts.vdf this install writes; resolved once for register and artwork."""
    root = steam or next((p for p in steam_tool.steam_roots() if (p/'userdata').is_dir()), None)
    if root is None:
        raise SystemExit('Steam install not found; pass --steam PATH')
    return steam_tool.select_shortcut(root, account)


def artwork_plan(shortcut, names):
    """Validate sources before shutdown and resolve Steam's exact grid slots."""
    manifest = json.loads(MANIFEST.read_text('utf-8'))
    mapping = manifest['artwork']
    grid = shortcut.parent/'grid'
    executable = str(TARGET.resolve())
    planned = []
    for name in names:
        appid = steam_tool.shortcut_appid(executable, name)
        for role, pattern in mapping.items():
            source = ARTWORK/role
            if not source.is_file():
                raise SystemExit(f'{source}: missing; run python steam/brand/make_brand_artwork.py')
            payload = source.read_bytes()
            if len(payload) < 24 or payload[:8] != b'\x89PNG\r\n\x1a\n' or payload[12:16] != b'IHDR':
                raise SystemExit(f'{source}: invalid PNG artwork')
            size = struct.unpack('>II', payload[16:24])
            if size != tuple(manifest['artwork_sizes'][role]):
                raise SystemExit(f'{source}: artwork size {size} differs from manifest')
            target = grid/pattern.replace('{appid}', str(appid))
            planned.append((role, target, payload, size))
    return planned


def install_artwork(shortcut, names, dry_run):
    """Install and verify images while Steam is closed, before its cache reload."""
    written = 0
    for role, target, payload, size in artwork_plan(shortcut, names):
        fresh = target.is_file() and target.read_bytes() == payload
        print(f'artwork  : {role:14} -> {target.name} ({"up to date" if fresh else "copy"})')
        # A hand-set JPG/JPEG in the same slot can take precedence over PNG.
        # Preserve it next to the file, outside Steam's recognized extensions.
        for extension in ('.jpg', '.jpeg'):
            alternate = target.with_suffix(extension)
            if alternate.is_file():
                print(f'artwork  : {"would back up" if dry_run else "back up"} {alternate.name}')
                if not dry_run:
                    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
                    alternate.replace(alternate.with_name(alternate.name + f'.bak-{stamp}'))
        if dry_run:
            continue
        if not fresh:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(payload)
            written += 1
        if target.read_bytes() != payload:
            raise SystemExit(f'{target}: artwork write verification failed')
    grid = shortcut.parent/'grid'
    print(f'artwork  : {grid} (dry run, nothing written)' if dry_run
          else f'artwork  : {written} file(s) written to {grid}')
    return 0


def verify_artwork(shortcut, names):
    """Check the actual files after Steam has reopened; do not claim UI visibility."""
    for role, target, payload, size in artwork_plan(shortcut, names):
        if not target.is_file() or target.read_bytes() != payload:
            raise SystemExit(f'{target}: artwork is missing or changed after installation')
        if any(target.with_suffix(extension).is_file() for extension in ('.jpg', '.jpeg')):
            raise SystemExit(f'{target}: conflicting artwork returned after installation')
        print(f'art checked: {target.name} {size[0]}x{size[1]} '
              f'sha256={hashlib.sha256(payload).hexdigest()}')
    print('artwork  : installed files verified; Steam display still requires visual confirmation')


def launch_options(suffix=''):
    """The editor binary needs --path; a user flag must follow `--` to reach the game."""
    line = f'--path "{ROOT}"'
    if suffix:
        # The browser scene resolves --continue-last. Before `--` the engine keeps the
        # flag as an unknown engine argument, so the game never sees it and opens the
        # world list - that was the "Last World" regression.
        line += f' {BROWSER_SCENE} -- {suffix}'
    return line


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--source', type=Path,
                        help='executable to copy (default: dist build, else the Godot editor)')
    parser.add_argument('--name', default=steam_tool.DEFAULT_NAME, help='Steam library name')
    parser.add_argument('--force', action='store_true', help='re-copy over TerraForest.exe')
    parser.add_argument('--dry-run', action='store_true', help='report without changing anything')
    parser.add_argument('--no-restart', action='store_true', help='leave Steam stopped')
    parser.add_argument('--last-world', action=argparse.BooleanOptionalAction, default=True,
                        help='register the "Last World" entry (default: yes)')
    parser.add_argument('--artwork', action=argparse.BooleanOptionalAction, default=True,
                        help="install Steam library artwork for both entries (default: yes)")
    parser.add_argument('--steam', type=Path, help='Steam install directory')
    parser.add_argument('--account', help='Steam account id under userdata')
    parser.add_argument('--progress', choices=('auto', 'bar', 'plain', 'off'), default='auto',
                        help='restart display: auto (bar on a terminal), bar, plain, off')
    parser.add_argument('--desktop', action=argparse.BooleanOptionalAction, default=True,
                        help='also (re)create the desktop shortcuts (default: yes)')
    parser.add_argument('--desktop-folder', type=Path,
                        help='desktop folder to write into (default: the real desktop)')
    parser.add_argument('--log', type=Path, help='run log file (default: steam/logs/install.log)')
    parser.add_argument('--no-log', action='store_true', help='do not write the run log')
    parser.add_argument('--confirm', action='store_true',
                        help='always show the restart approval dialog')
    parser.add_argument('--yes', '--no-confirm', dest='yes', action='store_true',
                        help='never ask; assume the restart is approved')
    parser.add_argument('--silent', action='store_true',
                        help='unattended run: no dialog and no progress output (--yes --progress off)')
    args = parser.parse_args()
    if args.silent:
        args.yes, args.progress = True, 'off'
    steam_tool.PROGRESS_MODE = args.progress
    if confirm_tool.should_confirm(args):
        steam_tool.CONFIRM = lambda detail: confirm_tool.ask(detail)
    with log_tool.run('install_to_steam', sys.argv[1:], args.log, enabled=not args.no_log) as run:
        run.code = deploy(args)
        return run.code


def deploy(args):
    """The actual install, run inside the log context."""
    source = args.source or next(iter(godot_sources(args.steam)), None)
    print(f'source   : {source or "<none found>"}')
    print(f'project  : {ROOT}')
    desktop_tool = load('add_desktop_shortcuts', ROOT/'steam'/'add_desktop_shortcuts.py')
    links = (args.desktop_folder or desktop_tool.desktop_folder()) if args.desktop else None
    if links:
        print(f'links    : {links}')
    prepare(source, args.force, args.dry_run)
    if not args.dry_run and not TARGET.is_file():
        raise SystemExit(f'{TARGET.name}: nothing to stamp; no source was copied')
    inspected = source if args.dry_run and (args.force or not TARGET.is_file()) else TARGET
    if not stamp(args.dry_run, inspected):
        raise SystemExit('icon stamping failed; the shortcut was not touched')
    names = [args.name] + ([f'{args.name} Last World'] if args.last_world else [])
    shortcut = shortcut_file(args.steam, args.account)
    print(f'account  : {shortcut.parents[1].name}')
    print(f'steam    : {shortcut.parents[3]}')
    print(f'file     : {shortcut}')
    if args.artwork:
        artwork_plan(shortcut, names)
    code = register(args.dry_run, args.name, not args.no_restart, args.force,
                    args.steam, args.account, args.last_world, shortcut=shortcut,
                    artwork=args.artwork, desktop=links)
    if code == 0 and args.artwork and not args.dry_run:
        verify_artwork(shortcut, names)
    if code == 0 and args.desktop:
        code = desktop_tool.create_shortcuts(links, args.dry_run, launch='steam',
                    exe=TARGET, name=args.name, shortcut=shortcut, last_world=args.last_world,
                    icon=ICON,
                    entries=wanted_entries(args.name, args.last_world, links)
                    if args.dry_run else None)
    if code == 0:
        print('done     : dry run complete; nothing changed' if args.dry_run
              else 'done     : TerraForest is prepared and registered')
    return code


if __name__ == '__main__':
    sys.exit(main())
