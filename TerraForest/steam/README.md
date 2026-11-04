# Steam installation

Double-click **`steam/install_to_steam.pyw`**. The normal install creates or repairs
all of these together:

- **TerraForest** and **TerraForest Last World** in the selected Steam account.
- Library artwork for both entries.
- Both desktop shortcuts, launching through the corresponding Steam entry.

Last World resolves the newest saved world when it launches. No saved world needs
to exist during installation. Re-running the installer repairs an older partial
installation; no extra flags are needed. A desktop shortcut is read back and its
Steam launch URL verified before installation reports success. Missing or invalid
Steam registration is an error, with no silent direct-executable fallback.

## One log to share

**`steam/logs/install.log`** contains dependency checks, console/windowed output,
stderr, exceptions, selected paths/account, entry names and app IDs, launch options,
verified desktop targets, and the actual result code. The installer hash identifies
which script ran on the other computer.

Use **Copy log** in the installer window to copy only the current/latest run for
pasting into a chat. The file retains earlier runs. Existing `gui.log` and
`history.tsv` are absorbed into this file once, preserving their contents, and
removed after successful copying. New runs do not create those separate files.
`--log PATH` redirects the whole run, including windowed dependency checks;
`--no-log` disables file logging.

## What is required

Use Windows with Python 3 and an existing Godot executable. Install **Godot Engine**
in any Steam library, or set `GODOT_EXE` / pass `--source PATH` for a standalone
installation. Export templates are unnecessary when running from project source.
Godot itself is not downloaded by this installer.

The installer keeps a project-root `TerraForest.exe` unless `--force` is passed.
When a copy is needed, automatic discovery checks `dist/TerraForest.exe`, then
`GODOT_EXE`, then Steam libraries, then native `godot.exe` / `godot4.exe` on PATH.
Command wrappers are not copied. Steam discovery covers:

- `--steam PATH`, registry roots, and standard Program Files Steam folders.
- Modern and legacy `libraryfolders.vdf`, escaped paths, spaces and Unicode.
- The Godot app manifest's installation directory.
- `godot.windows.opt.tools.64.exe`, `Godot Engine.exe`, and versioned
  `Godot*_win64*.exe` names, preferring the direct engine over its launcher.

The account is selected once, preferring Steam's active account, then the most
recent login, then local session timestamps. An account that has never added a
non-Steam game is supported: `shortcuts.vdf` is created as part of installation.
Sign into Steam once first if no account directory exists. `--account ID` selects
an existing account explicitly. Desktop creation uses this same account/file;
it does not search a second time or choose a different account.

The pair is merged in one write and at most one Steam restart. After shutdown,
the installer re-reads Steam's final saved file before merging, preserving other
games added during shutdown. Existing files are backed up beside `shortcuts.vdf`.
After restarting, both requested entries and their launch settings are verified.
An active game session blocks the restart until the game is finished.

## Console and optional controls

Run from the project root:

```powershell
python steam/lib/install_to_steam.py
python steam/lib/install_to_steam.py --dry-run --no-log
python steam/lib/install_to_steam.py --source 'C:\Tools\Godot\Godot_v4.7-stable_win64.exe'
```

A dry run works before `TerraForest.exe` exists. It inspects the source icon and
plans both Steam entries, artwork and desktop links without writing them. An icon
mismatch indicates that stamping is planned. It does not verify future write
permissions or the outcome of a real Steam restart.

| Option | Effect |
| --- | --- |
| `--no-last-world` | Explicitly skip installing the second entry/link |
| `--no-artwork` | Skip library artwork |
| `--no-desktop` | Skip desktop links |
| `--desktop-folder PATH` | Use a chosen desktop folder |
| `--steam PATH`, `--account ID` | Select the Steam installation/account |
| `--force` | Re-copy the engine; also permits restarting with a game session |
| `--no-restart` | Leave Steam closed after writing |
| `--progress auto\|bar\|plain\|off` | Select the console progress display |
| `--yes`, `--silent` | Unattended restart approval; silent also disables progress |

The window explains and approves the Steam restart. Console restart approval is
shown when interactive; `--confirm` forces it and `--yes` suppresses it. Cancellation
and failure are reported in the same log. Without Tk, the launcher runs the console
installer and records its output there. Missing Pillow, needed only for rebuilding
icon artwork, is handled by `steam/lib/ensure_deps.py` in the windowed launch.

## Other tools and resources

| Path | Role |
| --- | --- |
| `steam/uninstall_from_steam.pyw` | Remove both Steam entries and desktop links |
| `steam/lib/uninstall_from_steam.py` | Console removal; `--artwork` also removes images |
| `steam/add_desktop_shortcuts.py` | Repair both desktop links using existing Steam entries; Steam is the default route, `--launch native` is an explicit alternative |
| `steam/lib/steam_shortcuts.py` | Binary VDF handling, batch registration, backups and restart |
| `steam/lib/exe_source.py` | Local executable/library discovery |
| `steam/lib/install_log.py` | The single run log and latest-run copy text |
| `steam/lib/steam_gui.py` | Approval, progress, failure details and Copy log |
| `steam/manifest.json` | Tags and artwork mappings |
| `steam/brand/brand.json` | Editable artwork source; regenerate with `python steam/brand/make_brand_artwork.py` |
| `steam/artwork/` | Portrait, wide capsule, hero, logo and icon images |
| `steam/steam_trace.py` | Optional developer measurement of Steam startup |

The installer uses Steam's local non-Steam shortcut format. Artwork names are
computed from each actual entry's app ID; no machine-specific ID is hardcoded.

## Verification and remaining scope

```text
python -u -B -m unittest discover -s tests -t tests -p "test_*.py"
```

The regressions include real Windows Shell-link and VDF writes in temporary
folders, default options, first-time accounts, multi-account selection, one-restart
repair, shutdown-time data preservation, idempotence and unified failure logging.
Only Steam process control is simulated in these fixture tests.

The exported-build fallback still copies only its executable. Separate PCK/native
companion deployment remains outside this source-checkout installer; use the Godot
editor route until that packaging path is implemented and verified. Non-Windows
installation and the user's second computer have not been exercised here.
