# SPDX-License-Identifier: 0BSD
"""Add, list or remove a Steam shortcut for the TerraForest play build.

This is the shared engine behind `install_to_steam.py` and
`uninstall_from_steam.py`; run it directly only for one-off inspection
(`--list`) or surgery.

Steam has no supported API for non-Steam games. The entries live in
`<Steam>/userdata/<account>/config/shortcuts.vdf` as Valve's binary KeyValues,
and Steam keeps them in memory and rewrites that file when it exits - so an edit
made while Steam runs is discarded. The script therefore stops Steam, writes the
entry and starts Steam again by default; `--no-restart` leaves it stopped.
Existing entries are preserved byte for byte; the new one is appended before the
file's trailing terminator, and a timestamped backup is written beside it.

There is no live/protocol route: `steam://addnonsteamgame/...` is dispatched by
this Windows client (it appears as `ExecuteSteamURL` in the log) but opens no
dialog and writes no entry, so a Steam restart is unavoidable for a scripted add.

Usage:
    python steam/steam_shortcuts.py --dry-run      # show what would be added
    python steam/steam_shortcuts.py                # add, restarting Steam around the write
    python steam/steam_shortcuts.py --no-restart   # add, leave Steam stopped
    python steam/steam_shortcuts.py --list         # show current entries
    python steam/steam_shortcuts.py --remove       # drop the TerraForest entry
"""
from pathlib import Path
import argparse
import ctypes
import datetime
import os
import struct
import subprocess
import sys
import time
import winreg
import zlib
from ctypes import wintypes as w

# tools/ holds the progress display; keep the import working when loaded by path.
TOOL_DIR = Path(__file__).resolve().parent
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))
import steam_progress  # noqa: E402

# Lives in tools/; the play build is one level up next to project.godot.
ROOT = Path(__file__).resolve().parent.parent
CANDIDATE_EXES = (ROOT/'TerraForest.exe', ROOT/'Godot Engine TerraForest.exe',
                  ROOT/'dist/TerraForest.exe')
DEFAULT_NAME = 'TerraForest'
# One 0x08 closes a dictionary; the file's root end carries one extra 0x08 pad,
# which is the shape Steam itself writes (verified against a Steam-saved file).
KV_END = b'\x08\x08'
GAME_MARKER = 'gameoverlayui.exe'
STEAM_EXIT_TIMEOUT = 90
STEAM_START_TIMEOUT = 90
# Polling granularity: Steam's own shutdown/boot dominates, so waiting in whole
# seconds only added dead time at the end of each phase.
POLL = 0.25
# Measured: steam.exe appears almost at once, the first webhelper follows in ~0.1 s,
# and the process set then settles for a couple of seconds. Waiting for that quiet
# period is the closest thing to "Steam is ready" that Windows exposes.
STEAM_SETTLE = 1.0
# The client process is not the UI: wait for a visible Steam window to come back,
# and let it stand for a moment so the tray entry and its notification appear.
STEAM_UI_TIMEOUT = 20
STEAM_UI_GRACE = 2.0
# How the restart is reported: auto (bar on a terminal), bar, plain (one line per
# 10%, for logs) or off. The entry points set this from their --progress flag.
PROGRESS_MODE = 'auto'
# Launch Steam detached so our console closing cannot take the client with it.
DETACHED_PROCESS = 0x00000008
CREATE_NEW_PROCESS_GROUP = 0x00000200


def steam_roots():
    """Steam install directories from the registry, most specific first."""
    found = []
    for hive, key, value in ((winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam', 'SteamPath'),
                             (winreg.HKEY_LOCAL_MACHINE, r'SOFTWARE\WOW6432Node\Valve\Steam',
                              'InstallPath'),
                             (winreg.HKEY_LOCAL_MACHINE, r'SOFTWARE\Valve\Steam', 'InstallPath')):
        try:
            with winreg.OpenKey(hive, key) as handle:
                path = Path(winreg.QueryValueEx(handle, value)[0])
        except OSError:
            continue
        if path not in found:
            found.append(path)
    return found


def steam_processes():
    """{pid: name} for the watched Steam processes."""
    kernel = ctypes.WinDLL('kernel32')
    snapshot = kernel.CreateToolhelp32Snapshot(2, 0)  # TH32CS_SNAPPROCESS
    if snapshot in (0, -1):
        return {}

    class Entry(ctypes.Structure):
        _fields_ = [('dwSize', w.DWORD), ('cntUsage', w.DWORD), ('th32ProcessID', w.DWORD),
                    ('th32DefaultHeapID', ctypes.c_void_p), ('th32ModuleID', w.DWORD),
                    ('cntThreads', w.DWORD), ('th32ParentProcessID', w.DWORD),
                    ('pcPriClassBase', ctypes.c_long), ('dwFlags', w.DWORD),
                    ('szExeFile', ctypes.c_char * 260)]

    watched = {'steam.exe', 'steamwebhelper.exe', GAME_MARKER}
    entry, found = Entry(), {}
    entry.dwSize = ctypes.sizeof(Entry)
    kernel.Process32First(snapshot, ctypes.byref(entry))
    while True:
        name = entry.szExeFile.decode('mbcs', 'replace').lower()
        if name in watched:
            found[entry.th32ProcessID] = name
        if not kernel.Process32Next(snapshot, ctypes.byref(entry)):
            break
    kernel.CloseHandle(snapshot)
    return found


def steam_running():
    """Watched Steam process names: the client, its helpers and the game overlay."""
    return sorted(set(steam_processes().values()))


def steam_windows():
    """Top-level windows owned by a Steam process, hidden ones included.

    Measured: Steam runs with its main window hidden in the tray (title "Steam",
    class "SDL_app", 1280x744, IsWindowVisible false). Requiring it to be *visible*
    meant the wait could never finish, which is why the tool used to hand back
    before the tray entry and its notification were back. This reports the window's
    existence, and marks which one is the main window.
    """
    pids = set(steam_processes())
    if not pids:
        return []
    user32 = ctypes.WinDLL('user32')
    user32.GetWindowTextW.argtypes = [w.HWND, w.LPWSTR, ctypes.c_int]
    user32.GetClassNameW.argtypes = [w.HWND, w.LPWSTR, ctypes.c_int]
    user32.GetWindowThreadProcessId.argtypes = [w.HWND, ctypes.POINTER(w.DWORD)]
    user32.IsWindowVisible.argtypes = [w.HWND]
    user32.GetWindowRect.argtypes = [w.HWND, ctypes.POINTER(w.RECT)]
    found = []

    def visit(hwnd, _):
        pid = w.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value not in pids:
            return True
        title, klass = ctypes.create_unicode_buffer(256), ctypes.create_unicode_buffer(256)
        user32.GetWindowTextW(hwnd, title, 256)
        user32.GetClassNameW(hwnd, klass, 256)
        box = w.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(box))
        size = (box.right-box.left, box.bottom-box.top)
        if size[0] <= 0 or size[1] <= 0:
            return True
        found.append({'title': title.value, 'class': klass.value,
                      'visible': bool(user32.IsWindowVisible(hwnd)),
                      'size': size,
                      'main': title.value == 'Steam' and klass.value == 'SDL_app'})
        return True

    user32.EnumWindows(ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)(visit), 0)
    return found


def wait_for_steam_ui(timeout=STEAM_UI_TIMEOUT, progress=None, grace=STEAM_UI_GRACE,
                      windows=None):
    """Wait until Steam shows a window and has kept it for `grace` seconds."""
    lookup = windows or steam_windows
    deadline = time.time() + timeout
    ready_since = None
    while time.time() < deadline:
        live = lookup()
        main = next((win for win in live if win.get('main')), None)
        tray = next((win for win in live if win.get('class') == 'Chrome_StatusTrayWindow'), None)
        if ready_since is None and (main or tray):
            ready_since = time.time()
            if progress is not None:
                detail = (f"window {main['size'][0]}x{main['size'][1]}"
                          + ('' if main['visible'] else ', in the tray'))
                progress.tick(0.75, f'Steam UI ready ({detail})')
        elif ready_since is not None and time.time()-ready_since >= grace:
            if progress is not None:
                progress.tick(1.0, 'Steam is up: window and tray are back')
            return True
        elif progress is not None and ready_since is None:
            elapsed = 1 - max(0.0, (deadline-time.time())/timeout)
            progress.tick(0.5 + 0.25*elapsed, 'waiting for the Steam window')
        time.sleep(POLL)
    return False


def stop_steam(steam, timeout=STEAM_EXIT_TIMEOUT, progress=None):
    """Ask Steam to exit and wait until no Steam process is left."""
    executable = steam/'steam.exe'
    if not executable.is_file():
        raise SystemExit(f'{executable}: steam.exe not found')
    if 'steam.exe' not in steam_running():
        if progress is not None:
            progress.tick(1.0, 'Steam was already closed')
        return True  # already closed: nothing to wait for
    try:
        subprocess.run([str(executable), '-shutdown'], timeout=30,
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        pass  # the bootstrap may linger; the poll below is what decides
    deadline = time.time() + timeout
    while time.time() < deadline:
        # The client owns shortcuts.vdf; its helpers are torn down with it, and
        # waiting on them only added latency after the file was already safe.
        alive = steam_running()
        if 'steam.exe' not in alive:
            if progress is not None:
                progress.tick(1.0, 'all Steam processes gone')
            return True
        if progress is not None:
            left = max(0.0, (deadline - time.time())/timeout)
            elapsed_fraction = 1.0-left
            # Measured shutdown order: helpers go first, the client lingers ~0.3 s,
            # then everything is gone.
            if 'steamwebhelper.exe' not in alive:
                progress.tick(max(0.5, elapsed_fraction), 'helpers closed, client exiting')
            else:
                progress.tick(min(0.5, elapsed_fraction),
                              f'{len(alive)} process(es) left: {", ".join(alive)}')
        time.sleep(POLL)
    return False


def start_steam(steam, silent=True, timeout=STEAM_START_TIMEOUT, progress=None,
                settle=STEAM_SETTLE, wait_ui=True):
    """Start Steam again, then report the milestones measured in steam/traces.

    `steam.exe` becomes the client once it starts, so waiting for that process to
    exit - which `subprocess.run` does - blocks until Steam is closed again. That
    was the hang; launch detached and poll instead.
    """
    if 'steam.exe' in steam_running():
        if progress is not None:
            progress.tick(1.0, 'Steam relaunched itself')
        return True  # Steam relaunched itself after the shutdown
    executable = steam/'steam.exe'
    if not executable.is_file():
        raise SystemExit(f'{executable}: steam.exe not found')
    try:
        subprocess.Popen([str(executable)] + (['-silent'] if silent else []),
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, close_fds=True,
                         creationflags=DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP)
    except OSError as exc:
        print(f'warning  : could not launch Steam: {exc}', file=sys.stderr)
        return False
    deadline = time.time() + timeout
    client_up = helpers_up = False
    previous, stable_since = None, time.time()
    while time.time() < deadline:
        alive = set(steam_running())
        if 'steam.exe' in alive and not client_up:
            client_up = True
            if progress is not None:
                progress.tick(0.2, 'client process up')
        if 'steamwebhelper.exe' in alive and not helpers_up:
            helpers_up = True
            if progress is not None:
                progress.tick(0.5, 'helpers up (library loading)')
        if alive != previous:
            previous, stable_since = alive, time.time()
        elif client_up and time.time()-stable_since >= settle:
            if not wait_ui:
                if progress is not None:
                    progress.tick(1.0, 'process set settled')
                return True
            # Do not hand control back while Steam is still starting: wait for its
            # window, which is also when the tray icon and notification come back.
            if progress is not None:
                progress.tick(0.6, 'waiting for the Steam window')
            shown = wait_for_steam_ui(timeout=max(5.0, deadline-time.time()), progress=progress)
            if not shown and progress is not None:
                progress.tick(1.0, 'no window yet (Steam may be in the tray)')
            return True
        if progress is not None and not client_up:
            left = max(0.0, (deadline - time.time())/timeout)
            progress.tick(0.2*max(0.0, 1-left), 'waiting for steam.exe')
        time.sleep(POLL)
    return False


def accounts(steam):
    """Account directories that carry a shortcuts file, newest session first."""
    userdata = steam/'userdata'
    if not userdata.is_dir():
        raise SystemExit(f'{userdata}: no Steam userdata; is Steam installed here?')
    found = []
    for account in userdata.iterdir():
        shortcut = account/'config'/'shortcuts.vdf'
        local = account/'config'/'localconfig.vdf'
        if shortcut.is_file():
            found.append((local.stat().st_mtime if local.is_file() else 0, account.name, shortcut))
    if not found:
        raise SystemExit(f'{userdata}: no account has a shortcuts.vdf')
    return [item[2] for item in sorted(found, reverse=True)]


def read_dict(data, pos, target):
    """Read one binary KeyValues dictionary starting at pos."""
    while True:
        if pos >= len(data):
            raise SystemExit('shortcuts.vdf is truncated (Steam may be writing it)')
        if data[pos] == 0x08:
            # End of this dictionary. Some writers emit one 0x08 per dictionary,
            # ours emits two; accept one and let the caller absorb any padding.
            return pos + 1
        kind = data[pos]
        pos += 1
        end = data.index(b'\x00', pos)
        name = data[pos:end].decode('utf-8')
        pos = end + 1
        if kind == 0x00:
            child = {}
            target[name] = child
            pos = read_dict(data, pos, child)
        elif kind == 0x01:
            end = data.index(b'\x00', pos)
            target[name] = data[pos:end].decode('utf-8')
            pos = end + 1
        elif kind == 0x02:
            target[name] = struct.unpack_from('<i', data, pos)[0]
            pos += 4
        elif kind == 0x07:
            target[name] = struct.unpack_from('<Q', data, pos)[0]
            pos += 8
        else:
            raise SystemExit(f'unsupported KeyValues type 0x{kind:02x} at offset 0x{pos-1:x}')


def parse_shortcuts(data):
    """(root name, {index: fields}) for a shortcuts.vdf payload."""
    if not data or data[0] != 0x00:
        raise SystemExit('not a binary KeyValues file')
    end = data.index(b'\x00', 1)
    root = {}
    pos = read_dict(data, end + 1, root)
    while pos < len(data) and data[pos] == 0x08:
        pos += 1
    if pos != len(data):
        raise SystemExit(f'{len(data) - pos} unexpected trailing bytes in shortcuts.vdf')
    return data[1:end].decode('utf-8'), root


def write_dict(out, fields):
    for key, value in fields.items():
        if isinstance(value, dict):
            out += b'\x00' + key.encode('utf-8') + b'\x00'
            write_dict(out, value)
        elif isinstance(value, str):
            out += b'\x01' + key.encode('utf-8') + b'\x00' + value.encode('utf-8') + b'\x00'
        elif isinstance(value, int):
            out += b'\x02' + key.encode('utf-8') + b'\x00' + struct.pack('<i', value)
        else:
            raise SystemExit(f'cannot encode {key}={value!r}')
    out += b'\x08'


def serialize_shortcuts(root_name, entries):
    out = bytearray(b'\x00' + root_name.encode('utf-8') + b'\x00')
    write_dict(out, {str(index): fields for index, fields in sorted(entries.items())})
    out += b'\x08'
    return bytes(out)


def shortcut_fields(name, exe, launch_options='', icon='', tags=()):
    return {
        # The documented entry format carries its own app id; Steam rewrote a
        # file whose entries lack it, dropping them, so it is always written.
        'appid': signed32(shortcut_appid(exe, name)),
        'AppName': name,
        'Exe': f'"{exe}"',
        'StartDir': f'"{exe.parent}"',
        'icon': str(icon),
        'ShortcutPath': '',
        'LaunchOptions': launch_options,
        'IsHidden': 0,
        'AllowDesktopConfig': 1,
        'AllowOverlay': 1,
        'OpenVR': 0,
        'Devkit': 0,
        'DevkitGameID': '',
        'DevkitOverrideAppID': 0,
        'LastPlayTime': 0,
        'FlatpakAppID': '',
        'sortas': '',
        # Steam stores tags as index -> name pairs: "tags" { "0" "World building" }.
        # Writing {name: 1} instead made Steam collapse the whole set to {"0": "1"}.
        'tags': {str(index): str(tag) for index, tag in enumerate(tags)},
    }


def shortcut_appid(exe, name):
    """Steam's non-Steam shortcut id, used to name library artwork files."""
    return (zlib.crc32(f'"{exe}"{name}'.encode('utf-8')) & 0xFFFFFFFF) | 0x80000000


def signed32(value):
    """KeyValues int32 is signed; the app id is an unsigned 32-bit value."""
    return value - 0x100000000 if value >= 0x80000000 else value


def matches(fields, name, exe):
    """One entry is identified by its executable plus its name.

    Two shortcuts may point at the same executable (the plain launch and the
    "continue last world" launch), so the name has to take part in the identity;
    matching on the executable alone silently rewrote the other entry.
    """
    stored = (fields.get('Exe') or '').strip('"').replace('/', '\\').lower()
    if stored != str(exe).replace('/', '\\').lower():
        return False
    wanted = (name or '').strip().lower()
    return not wanted or (fields.get('AppName') or '').strip().lower() == wanted


def find_entry(entries, name, exe):
    return {index: fields for index, fields in entries.items() if matches(fields, name, exe)}


def load(path):
    # Steam rewrites this file; a read that lands mid-write is truncated, so retry
    # before reporting, and fail with a clear message rather than an index error.
    error = None
    for _ in range(10):
        try:
            data = path.read_bytes()
            root, entries = parse_shortcuts(data)
            break
        except (SystemExit, IndexError, OSError) as exc:
            error = exc
            time.sleep(0.2)
    else:
        raise SystemExit(f'{path}: cannot be read right now ({error})')
    if serialize_shortcuts(root, entries) != data:
        print(f'warning: {path} does not round-trip byte for byte; '
              'only appending, never rewriting', file=sys.stderr)
    return data, root, entries


def write_bytes(path, payload):
    """Write with retries: Steam releases the file a moment after it exits."""
    error = None
    for _ in range(40):
        try:
            temporary = path.with_name(path.name + '.tmp')
            temporary.write_bytes(payload)
            os.replace(temporary, path)
            return
        except PermissionError as exc:
            error = exc
            time.sleep(0.25)
    raise SystemExit(f'{path}: could not write: {error}')


def commit(shortcut, original, candidate, label, restart, force, progress=None):
    """Stop Steam if needed, replace the file, verify, and restart Steam."""
    steam = shortcut.parents[3]
    running = steam_running()
    bar = progress if progress is not None else steam_progress.Progress(mode=PROGRESS_MODE)
    bar.stage('check', f'{len(running)} process(es): {", ".join(running) or "none"}')
    if running:
        if GAME_MARKER in running and not force:
            print(f'refusing : a Steam game session looks active ({", ".join(running)}); '
                  'stopping Steam would end it.\n'
                  '           Finish the game, or pass --force.', file=sys.stderr)
            bar.abort('refused: a game session is active')
            return 2
        print(f'stopping : Steam ({", ".join(running)}) so it cannot overwrite the file')
        bar.stage('stop', f'closing {", ".join(running)}')
        if not stop_steam(steam, progress=bar):
            print('refusing : Steam did not exit in time; nothing written', file=sys.stderr)
            bar.abort('failed: Steam did not exit')
            return 2
    else:
        bar.stage('stop', 'Steam was not running')
        bar.tick(1.0)

    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup = shortcut.with_name(shortcut.name + f'.bak-{stamp}')
    bar.stage('write')
    backup.write_bytes(original)
    write_bytes(shortcut, candidate)
    print(f'backup   : {backup}')
    print(label)
    bar.tick(1.0, 'file written')

    status = 0
    if not running:
        # Nothing was stopped, so nothing needs starting: Steam reads this on its
        # next launch, and launching it unasked would be a surprise.
        print('note     : Steam was not running; it will read this at its next start')
        bar.stage('start', 'not needed: Steam was closed')
        bar.tick(1.0)
    elif restart:
        bar.stage('start', 'waiting for steam.exe')
        if start_steam(steam, progress=bar):
            print('started  : Steam')
            status = verify_after_restart(shortcut, bar)
        else:
            print('warning  : Steam did not start again; start it yourself', file=sys.stderr)
            bar.abort('warning: Steam did not start')
            status = 1
    else:
        print('stopped  : Steam left stopped (--no-restart); it reads this at its next start')
        bar.stage('start', 'skipped: --no-restart')
        bar.tick(1.0)
    if status == 0:
        bar.finish('done')
    return status


def verify_after_restart(shortcut, bar):
    """Re-read the file Steam just took over; its own rewrite is what could break it."""
    bar.stage('verify', 're-reading shortcuts.vdf')
    # Re-read immediately: a fixed settle only delayed the answer when the file was
    # already fine. Retry briefly only if Steam is mid-write.
    entries = None
    for attempt in range(5):
        try:
            _, entries = parse_shortcuts(shortcut.read_bytes())
            break
        except (SystemExit, OSError):
            bar.tick((attempt+1)/5, 'Steam is still writing the file')
            time.sleep(0.2)
    if entries is None:
        print('warning  : could not re-read shortcuts.vdf yet; Steam may still be '
              'writing it', file=sys.stderr)
        bar.tick(1.0, 'unreadable')
        return 1
    print(f'checked  : shortcuts.vdf still holds {len(entries)} entry(ies)')
    bar.tick(1.0, f'{len(entries)} entr(ies) intact')
    return 0


def set_launch_options(shortcut, name, exe, launch_options, dry_run=False, restart=True,
                       force=False):
    """Rewrite one existing entry's LaunchOptions, keeping everything else as is."""
    data, root, entries = load(shortcut)
    found = find_entry(entries, name, exe)
    if not found:
        print(f'no "{name}" shortcut in {shortcut}; nothing to update')
        return 0
    index = next(iter(found))
    current = entries[index].get('LaunchOptions', '')
    if current == launch_options:
        print(f'"{name}" already launches with {launch_options!r}; nothing to do')
        return 0
    updated = dict(entries)
    updated[index] = dict(entries[index], LaunchOptions=launch_options)
    candidate = serialize_shortcuts(root, updated)
    check_root, check_entries = parse_shortcuts(candidate)
    if check_root != root or len(check_entries) != len(entries) or \
       check_entries[index].get('LaunchOptions') != launch_options:
        raise SystemExit('refusing to write: the candidate file failed its own round-trip check')
    print(f'options  : "{name}" {current!r} -> {launch_options!r}')
    if dry_run:
        print('dry run  : nothing written, Steam untouched')
        return 0
    return commit(shortcut, data, candidate,
                  f'updated  : entry {index} launch options', restart, force)


def add(shortcut, name, exe, dry_run, restart=True, force=False, launch_options='',
        icon='', tags=()):
    data, root, entries = load(shortcut)
    duplicate = find_entry(entries, name, exe)
    if duplicate:
        index = next(iter(duplicate))
        fields = dict(duplicate[index])
        wanted_tags = {str(index): str(tag) for index, tag in enumerate(tags)}
        changes = {}
        if launch_options and fields.get('LaunchOptions', '') != launch_options:
            changes['LaunchOptions'] = launch_options
        if icon and str(icon) != fields.get('icon', ''):
            changes['icon'] = str(icon)
        if wanted_tags and fields.get('tags', {}) != wanted_tags:
            changes['tags'] = wanted_tags
        if not changes:
            print(f'"{name}" is already a shortcut in {shortcut} (index '
                  f'{index}); nothing to do')
            return 0
        fields.update(changes)
        updated = dict(entries)
        updated[index] = fields
        candidate = serialize_shortcuts(root, updated)
        check_root, check_entries = parse_shortcuts(candidate)
        if check_root != root or len(check_entries) != len(entries) or \
           any(check_entries[index].get(key) != value for key, value in changes.items()):
            raise SystemExit('refusing to write: the candidate file failed its own round-trip check')
        print(f'updated  : "{name}" {", ".join(sorted(changes))}')
        if dry_run:
            print('dry run  : nothing written, Steam untouched')
            return 0
        return commit(shortcut, data, candidate,
                      f'updated  : entry {index} {", ".join(sorted(changes))}', restart, force)
    index = max((int(k) for k in entries), default=-1) + 1
    fields = shortcut_fields(name, exe, launch_options, icon, tags)
    updated = dict(entries)
    updated[str(index)] = fields
    # Serialised from the parsed entries rather than spliced into the original
    # bytes: Steam rewrites the file with its own terminator layout, and splicing
    # into that produced trailing garbage.
    candidate = serialize_shortcuts(root, updated)
    check_root, check_entries = parse_shortcuts(candidate)
    if check_root != root or len(check_entries) != len(entries) + 1 or \
       not matches(check_entries[str(index)], name, exe):
        raise SystemExit('refusing to write: the candidate file failed its own round-trip check')
    print(f'shortcut : "{name}" -> {exe}')
    print(f'file     : {shortcut} ({len(data)} -> {len(candidate)} bytes)')
    appid = shortcut_appid(exe, name)
    print(f'app id   : {appid} (artwork would be {appid}.png)')
    if dry_run:
        print('dry run  : nothing written, Steam untouched')
        return 0
    return commit(shortcut, data, candidate,
                  f'added    : entry {index} of {len(check_entries)}', restart, force)


def remove(shortcut, name, exe, dry_run, restart=True, force=False):
    data, root, entries = load(shortcut)
    victim = find_entry(entries, name, exe)
    if not victim:
        print(f'no "{name}" shortcut in {shortcut}; nothing to remove')
        return 0
    remaining = {index: fields for index, fields in entries.items() if index not in victim}
    candidate = serialize_shortcuts(root, remaining)
    print(f'removing : "{name}" (index {", ".join(victim)}) from {shortcut}')
    if dry_run:
        print('dry run  : nothing written, Steam untouched')
        return 0
    return commit(shortcut, data, candidate,
                  f'removed  : entry {", ".join(victim)}; {len(remaining)} left', restart, force)


def remove_all(shortcut, names, exe, dry_run, restart=True, force=False):
    """Remove several named entries in one pass, so Steam is restarted once."""
    data, root, entries = load(shortcut)
    victims = {}
    for name in names:
        found = find_entry(entries, name, exe)
        if not found:
            print(f'missing  : no "{name}" entry in {shortcut}')
            continue
        victims.update(found)
    if not victims:
        print(f'nothing  : no entry of {", ".join(names)} to remove')
        return 0
    labels = ', '.join(f'"{entries[index].get("AppName")}" (index {index})'
                       for index in sorted(victims, key=int))
    remaining = {index: fields for index, fields in entries.items() if index not in victims}
    candidate = serialize_shortcuts(root, remaining)
    check_root, check_entries = parse_shortcuts(candidate)
    if check_root != root or len(check_entries) != len(entries) - len(victims):
        raise SystemExit('refusing to write: the candidate file failed its own round-trip check')
    print(f'removing : {labels} from {shortcut}')
    if dry_run:
        print('dry run  : nothing written, Steam untouched')
        return 0
    return commit(shortcut, data, candidate,
                  f'removed  : {len(victims)} entry(ies); {len(remaining)} left',
                  restart, force)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--exe', type=Path, help='executable to add (default: project build)')
    parser.add_argument('--name', default=DEFAULT_NAME, help='library name')
    parser.add_argument('--steam', type=Path, help='Steam install directory')
    parser.add_argument('--account', help='Steam account id under userdata')
    parser.add_argument('--list', action='store_true', help='list current shortcuts')
    parser.add_argument('--remove', action='store_true', help='remove the shortcut')
    parser.add_argument('--launch-options', default='',
                        help='arguments Steam passes on top of Exe (e.g. --path "<project>")')
    parser.add_argument('--dry-run', action='store_true', help='report without touching Steam')
    parser.add_argument('--no-restart', action='store_true',
                        help='stop Steam for the write but leave it stopped afterwards')
    parser.add_argument('--force', action='store_true',
                        help='stop Steam even if a game session looks active')
    parser.add_argument('--progress', choices=steam_progress.MODES, default='auto',
                        help='restart display: auto (bar on a terminal), bar, plain, off')
    args = parser.parse_args()
    global PROGRESS_MODE
    PROGRESS_MODE = args.progress

    steam = args.steam or next((p for p in steam_roots() if (p/'userdata').is_dir()), None)
    if steam is None:
        parser.error('Steam install not found; pass --steam PATH')
    if args.account:
        shortcut = steam/'userdata'/args.account/'config'/'shortcuts.vdf'
        if not shortcut.is_file():
            parser.error(f'no shortcuts.vdf for account {args.account}')
    else:
        shortcut = accounts(steam)[0]

    if args.list:
        _, _, entries = load(shortcut)
        print(f'{shortcut}: {len(entries)} shortcut(s)')
        for index, fields in sorted(entries.items(), key=lambda item: int(item[0])):
            appid = fields.get('appid')
            tag = f'[{appid & 0xFFFFFFFF}]' if isinstance(appid, int) else '[no appid]'
            options = fields.get('LaunchOptions') or ''
            print(f'  {index}: {fields.get("AppName")}  {fields.get("Exe")}  {tag}'
                  + (f'  opts={options}' if options else '  opts=<none>'))
        return 0

    exe = args.exe or next((p for p in CANDIDATE_EXES if p.exists()), None)
    if exe is None or not exe.exists():
        parser.error('executable not found; pass --exe PATH')
    exe = exe.resolve()
    restart, force = not args.no_restart, args.force
    if args.remove:
        return remove(shortcut, args.name, exe, args.dry_run, restart, force)
    return add(shortcut, args.name, exe, args.dry_run, restart, force, args.launch_options)


if __name__ == '__main__':
    sys.exit(main())
