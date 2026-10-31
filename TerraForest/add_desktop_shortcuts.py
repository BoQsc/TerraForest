# SPDX-License-Identifier: 0BSD
"""Put "TerraForest" and "TerraForest Last World" on the desktop, or refresh them.

Both shortcuts start the play build the same way the game starts itself
(`demo/world_launch.gd`): the executable plus `--path <project>`, and for the
world one `res://demo/worlds.tscn -- --continue-last`, which lets the game pick
the world itself instead of naming a slot in the shortcut.

If Steam already has an entry whose launch options match a shortcut's arguments
(`tools/steam_shortcuts.py`), that shortcut launches through Steam
(`steam://rungameid/<id>`) so the overlay and playtime apply, and only falls back
to the executable when no entry carries that exact argument string. `--launch
steam` or `--launch native` force either route.

*TerraForest* opens the world list. *TerraForest Last World* continues the newest
world, chosen by the game itself (it orders saves by last played). Re-running the
script rewrites both shortcuts in place.

Usage:
    python add_desktop_shortcuts.py               # create or update both
    python add_desktop_shortcuts.py --dry-run     # report only
    python add_desktop_shortcuts.py --launch steam  # force the Steam route
    python add_desktop_shortcuts.py --folder DIR  # somewhere other than the desktop
"""
from pathlib import Path
import argparse
import ctypes
import importlib.util
import os
import sys
import uuid
from ctypes import wintypes as w

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT
WORLD_SCENE = 'res://demo/world.tscn'
# The scene that reads --continue-last (the browser); it is also the main scene.
BROWSER_SCENE = 'res://demo/worlds.tscn'
WORLD_ARGS = ['--ground-cover', '--actors', '--vehicle-fleet', '--max-fps=60']
RUNDLL = Path(os.environ.get('SystemRoot', r'C:\Windows'))/'System32'/'rundll32.exe'
# Steam's "long" app id for a non-Steam shortcut: (shortcut app id << 32) | 0x02000000.
SHORTCUT_APPID_FLAG = 0x02000000

ole32 = ctypes.OleDLL('ole32')
ole32.CoInitializeEx.argtypes = [ctypes.c_void_p, w.DWORD]
ole32.CoCreateInstance.argtypes = [ctypes.c_void_p, ctypes.c_void_p, w.DWORD,
                                   ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
ole32.CoTaskMemFree.argtypes = [ctypes.c_void_p]
shell32 = ctypes.WinDLL('shell32')
shell32.SHGetKnownFolderPath.argtypes = [ctypes.c_void_p, w.DWORD, w.HANDLE,
                                         ctypes.POINTER(ctypes.c_void_p)]
shell32.SHGetKnownFolderPath.restype = ctypes.c_long
CLSCTX_INPROC_SERVER = 1
CLSID_SHELLLINK = '{00021401-0000-0000-C000-000000000046}'
IID_ISHELLLINKW = '{000214F9-0000-0000-C000-000000000046}'
IID_IPERSISTFILE = '{0000010B-0000-0000-C000-000000000046}'
FOLDERID_DESKTOP = '{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}'


def project_name(project_file=PROJECT/'project.godot'):
    """config/name from project.godot, which is also the user:// folder name."""
    for line in project_file.read_text('utf-8', 'replace').splitlines():
        if line.startswith('config/name='):
            return line.split('=', 1)[1].strip().strip('"')
    raise SystemExit(f'{project_file}: no config/name')


def user_dir(project_file=PROJECT/'project.godot'):
    """Godot's user:// folder: app_userdata/<name>, or a configured custom folder."""
    settings = {}
    for line in project_file.read_text('utf-8', 'replace').splitlines():
        if line.startswith('application/config/'):
            key, _, value = line.partition('=')
            settings[key.strip()] = value.strip().strip('"')
    appdata = Path(os.environ['APPDATA'])
    custom = settings.get('application/config/custom_user_dir_name')
    if custom and settings.get('application/config/use_custom_user_dir', '').lower() == 'true':
        return appdata/custom
    return appdata/'Godot'/'app_userdata'/project_name(project_file)


def worlds_dir(project_file=PROJECT/'project.godot'):
    return user_dir(project_file)/'worlds'


def shortcut_names(project_file=PROJECT/'project.godot'):
    """Both .lnk names, derived from the project name rather than fixed here."""
    name = project_name(project_file)
    return f'{name}.lnk', f'{name} Last World.lnk'


def newest_world(directory):
    """Newest saved world slot: the game orders by last_played, then by save time."""
    if not directory.is_dir():
        return None
    worlds = sorted(directory.glob('*.trw'), key=lambda p: p.stat().st_mtime, reverse=True)
    return worlds[0].stem if worlds else None


def launch_arguments(slot=None):
    """Engine and user arguments for the game's own launch line."""
    base = ['--path', str(PROJECT)]
    if slot is None:
        return base
    return base + ['--fullscreen', '--resolution', '1920x1080', '--max-fps', '60',
                   WORLD_SCENE, '--', f'--world-slot={slot}'] + WORLD_ARGS


def command_line(arguments):
    """Windows command line for a .lnk: quote any argument containing a space."""
    return ' '.join(f'"{argument}"' if ' ' in argument else argument
                    for argument in arguments)


def continue_arguments():
    """Static "continue the newest world" command line; the game picks the slot."""
    # The flag must follow the `--` separator: the game reads OS.get_cmdline_user_args(),
    # and anything before `--` is an engine argument that never reaches the game.
    # The browser scene is the one that resolves it (the world scene ignores it).
    return launch_arguments() + [BROWSER_SCENE, '--', '--continue-last']


def desktop_folder():
    """The real desktop, honouring a redirected (OneDrive) profile."""
    raw = ctypes.c_void_p()
    guid = _guid(FOLDERID_DESKTOP)
    if shell32.SHGetKnownFolderPath(ctypes.byref(guid), 0, None, ctypes.byref(raw)) == 0:
        try:
            return Path(ctypes.wstring_at(raw.value))
        finally:
            ole32.CoTaskMemFree(raw)
    return Path(os.environ['USERPROFILE'])/'Desktop'


class GUID(ctypes.Structure):
    _fields_ = [('Data1', w.DWORD), ('Data2', w.WORD), ('Data3', w.WORD),
                ('Data4', ctypes.c_ubyte * 8)]


def _guid(text):
    value = GUID()
    ctypes.memmove(ctypes.byref(value), uuid.UUID(text).bytes_le, 16)
    return value


def _vtable_method(pointer, index, restype, *argtypes):
    vtable = ctypes.cast(pointer, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
    prototype = ctypes.WINFUNCTYPE(restype, ctypes.c_void_p, *argtypes)
    return prototype(vtable[index])


def _shell_link():
    ole32.CoInitializeEx(None, 2)  # STA
    pointer = ctypes.c_void_p()
    clsid, iid = _guid(CLSID_SHELLLINK), _guid(IID_ISHELLLINKW)
    result = ole32.CoCreateInstance(ctypes.byref(clsid), None, CLSCTX_INPROC_SERVER,
                                    ctypes.byref(iid), ctypes.byref(pointer))
    if result != 0 or not pointer:
        raise SystemExit(f'CoCreateInstance(IShellLink) failed: 0x{result & 0xFFFFFFFF:08x}')
    return pointer


def write_shortcut(link, target, arguments, working_directory, description, icon):
    """Create or overwrite one .lnk through IShellLink + IPersistFile."""
    pointer = _shell_link()
    for index, text in ((20, str(target)), (11, arguments), (9, str(working_directory)),
                        (7, description)):
        method = _vtable_method(pointer, index, ctypes.c_long, ctypes.c_wchar_p)
        if method(pointer, text) != 0:
            raise SystemExit(f'IShellLink call {index} failed for {link}')
    icon_method = _vtable_method(pointer, 17, ctypes.c_long, ctypes.c_wchar_p, ctypes.c_int)
    icon_method(pointer, str(icon), 0)
    show = _vtable_method(pointer, 15, ctypes.c_long, ctypes.c_int)
    show(pointer, 1)  # SW_SHOWNORMAL

    persist = ctypes.c_void_p()
    query = _vtable_method(pointer, 0, ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p)
    iid = _guid(IID_IPERSISTFILE)
    if query(pointer, ctypes.byref(iid), ctypes.byref(persist)) != 0 or not persist:
        raise SystemExit(f'{link}: IPersistFile not available')
    save = _vtable_method(persist, 6, ctypes.c_long, ctypes.c_wchar_p, ctypes.c_int)
    if save(persist, str(link), 1) != 0:
        raise SystemExit(f'{link}: Save failed')


def read_shortcut(link):
    """(target, arguments) of an existing .lnk, for checking the result."""
    pointer = _shell_link()
    persist = ctypes.c_void_p()
    query = _vtable_method(pointer, 0, ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p)
    iid = _guid(IID_IPERSISTFILE)
    if query(pointer, ctypes.byref(iid), ctypes.byref(persist)) != 0 or not persist:
        raise SystemExit(f'{link}: IPersistFile not available')
    load = _vtable_method(persist, 5, ctypes.c_long, ctypes.c_wchar_p, ctypes.c_int)
    if load(persist, str(link), 0) != 0:
        raise SystemExit(f'{link}: Load failed')
    buffer = ctypes.create_unicode_buffer(1024)
    _vtable_method(pointer, 3, ctypes.c_long, ctypes.c_wchar_p, ctypes.c_int,
                   ctypes.c_void_p, w.DWORD)(pointer, buffer, 1024, None, 0)
    target = buffer.value
    arguments = ctypes.create_unicode_buffer(4096)
    _vtable_method(pointer, 10, ctypes.c_long, ctypes.c_wchar_p, ctypes.c_int)(
        pointer, arguments, 4096)
    return target, arguments.value


_STEAM = None


def steam():
    """The tools/ module that owns shortcuts.vdf, loaded once."""
    global _STEAM
    if _STEAM is None:
        spec = importlib.util.spec_from_file_location('steam_shortcuts',
                                                      ROOT/'tools'/'steam_shortcuts.py')
        if spec is None or spec.loader is None:
            raise SystemExit(f'{ROOT}/tools/steam_shortcuts.py: cannot be imported')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _STEAM = module
    return _STEAM


def steam_entry(exe, name):
    """(shortcuts file, fields) when Steam already has this game, else (None, None)."""
    tool = steam()
    for root in [p for p in tool.steam_roots() if (p/'userdata').is_dir()]:
        for shortcut in tool.accounts(root):
            try:
                _, _, entries = tool.load(shortcut)
            except (SystemExit, OSError):
                continue
            found = tool.find_entry(entries, name, exe)
            if found:
                index = next(iter(found))
                return shortcut, found[index]
    return None, None


def long_app_id(appid):
    """Steam's 64-bit "rungameid" form of a non-Steam shortcut id."""
    return ((appid & 0xFFFFFFFF) << 32) | SHORTCUT_APPID_FLAG


def steam_command(appid):
    """Target and arguments that hand steam://rungameid/<id> to the client."""
    return RUNDLL, ['url.dll,FileProtocolHandler', f'steam://rungameid/{long_app_id(appid)}']


def steam_route(entry, required, mode):
    """The Steam command for an entry, or None when it cannot launch what we ask."""
    if mode == 'native' or not entry:
        return None
    appid = entry.get('appid')
    if not isinstance(appid, int):
        return None
    if mode == 'steam' or (entry.get('LaunchOptions') or '') == required:
        return steam_command(appid)
    return None


def plan(folder, slot=None, name=None, exe=None, plain_entry=None, world_entry=None,
         mode='auto'):
    """Shortcuts to write: Steam when its entry launches what we ask, else native."""
    name = name or project_name()
    exe = exe or ROOT/f'{name}.exe'
    entries = []

    plain = steam_route(plain_entry, command_line(launch_arguments()), mode)
    if plain:
        target, arguments = plain
        state = f'steam (appid {plain_entry["appid"] & 0xFFFFFFFF})'
    else:
        target, arguments, state = exe, launch_arguments(None), 'native'
    entries.append({'link': folder/f'{name}.lnk', 'target': target,
                    'arguments': arguments, 'description': f'Play {name}', 'mode': state})

    # The last-world shortcut carries no slot: --continue-last lets the game decide,
    # which is what makes a fixed Steam command line able to express it.
    world = steam_route(world_entry, command_line(continue_arguments()), mode)
    if world:
        target, arguments = world
        state = f'steam (appid {world_entry["appid"] & 0xFFFFFFFF})'
    else:
        target, arguments, state = exe, continue_arguments(), 'native'
    entries.append({'link': folder/f'{name} Last World.lnk', 'target': target,
                    'arguments': arguments, 'description': f'Continue {name}',
                    'mode': state})
    return entries


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--folder', type=Path, help='where to put the shortcuts (default: desktop)')
    parser.add_argument('--exe', type=Path, default=ROOT/f'{project_name()}.exe',
                        help='executable the shortcuts start')
    parser.add_argument('--worlds-dir', type=Path, help='override the user://worlds folder')

    parser.add_argument('--launch', choices=('auto', 'steam', 'native'), default='auto',
                        help='launch through Steam when it has the game (default: auto)')
    parser.add_argument('--dry-run', action='store_true', help='report without writing')
    args = parser.parse_args()

    folder = args.folder or desktop_folder()
    if not args.exe.is_file():
        raise SystemExit(f'{args.exe}: missing; run install_to_steam.py first')
    slot = newest_world(args.worlds_dir or worlds_dir())
    name = project_name()
    plain_file, plain_fields = steam_entry(args.exe, name)
    world_file, world_fields = steam_entry(args.exe, f'{name} Last World')

    def describe(label, entry_file, fields):
        if fields is None:
            print(f'{label:8} : not registered')
            return
        number = fields.get('appid')
        number = number & 0xFFFFFFFF if isinstance(number, int) else '?'
        print(f'{label:8} : {entry_file}  appid {number}  '
              f'opts={fields.get("LaunchOptions") or "<none>"}')

    describe('steam', plain_file, plain_fields)
    describe('last', world_file, world_fields)
    print(f'folder   : {folder}')
    print(f'exe      : {args.exe}')
    print(f'world    : {slot or "<no saves yet>"} (resolved by the game at launch)')

    status = 0
    for item in plan(folder, slot, name, args.exe, plain_fields, world_fields, args.launch):
        link = item['link']
        action = 'update' if link.exists() else 'create'
        if args.dry_run:
            print(f'{action:8} : {link.name} [{item["mode"]}]\n'
                  f'           {item["target"]} {command_line(item["arguments"])}')
            continue
        write_shortcut(link, item['target'], command_line(item['arguments']), ROOT,
                       item['description'], args.exe)
        target, stored = read_shortcut(link)
        print(f'{action}d  : {link.name} [{item["mode"]}] -> {target}\n           {stored}')
        if Path(target).resolve() != item['target'].resolve() or not stored:
            print(f'warning  : {link.name} did not read back as expected', file=sys.stderr)
            status = 1

    if args.launch != 'native':
        for label, fields, wanted in (
                (name, plain_fields, command_line(launch_arguments())),
                (f'{name} Last World', world_fields, command_line(continue_arguments()))):
            if fields is not None and (fields.get('LaunchOptions') or '') != wanted:
                print(f'note     : the Steam entry "{label}" launches with '
                      f'{fields.get("LaunchOptions") or "<no options>"!r}, so Steam cannot '
                      f'run it correctly. Register it with this launch option:\n'
                      f'           {wanted}\n'
                      f'           python tools/steam_shortcuts.py --name "{label}" '
                      f'--launch-options <that value>')
    if args.dry_run:
        print('dry run  : nothing written')
    return status


if __name__ == '__main__':
    sys.exit(main())
