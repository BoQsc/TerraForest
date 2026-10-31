# Steam installation resources

Everything that decides how TerraForest appears in Steam lives here, so the choices are
visible and reviewable before anything touches `shortcuts.vdf` or the Steam grid folder.

The three tools live here too, next to the resources they apply. `manifest.json` and
`artwork/` are not read by the installer yet — they are the source of truth to wire up next.
The placeholders are real images at Steam's exact sizes, so replacing them is a drop-in.

`artwork/` is generated from `brand/brand.json` (`python steam/brand/make_brand_artwork.py`);
edit the brand, not the PNGs.

## Tools

| Script | What it does |
|---|---|
| `install_to_steam.py` | copy the build, stamp the icon, register in Steam (`--last-world` adds the second entry, `--artwork` installs the images) |
| `uninstall_from_steam.py` | remove both Steam entries, the desktop shortcuts and (with `--artwork`) the grid images in one pass, with backup and restart (`--list`, `--dry-run`, `--name`, `--no-desktop` keeps the .lnk files, `--desktop-folder` for a redirected desktop) |
| `add_desktop_shortcuts.py` | create or refresh the two desktop shortcuts, preferring the Steam launch when an entry matches |

All three are run from the project root, e.g. `python steam/install_to_steam.py --dry-run`.
The shared `shortcuts.vdf` engine stays in `steam/steam_shortcuts.py`.

## Progress during a Steam restart

Writes need Steam stopped, so every add/update/remove stops it, writes, and starts it
again. While that happens `steam/steam_progress.py` draws one updating line:

```
[#########---------------]  38%  Stopping Steam · 2 process(es) left: steam.exe, steamwebhelper.exe
[############------------]  50%  Writing shortcuts.vdf · file written
[#####################---]  90%  Starting Steam · waiting for steam.exe
[########################] 100%  Verifying the file · 2 entr(ies) intact
```

The percentages come from the process list, not a timer: the stop stage polls how many
Steam processes are still alive, the start stage polls for `steam.exe` to return, and the
verify stage re-reads `shortcuts.vdf`. It draws only on a terminal and stays silent when
output is piped, so scripts and tests keep their plain lines.
Preview the stages without touching Steam: `python steam/steam_progress.py --demo`.

Every tool takes `--progress auto|bar|plain|off`:

- `auto` (default) — the animated single line on a terminal, silent when piped;
- `bar` — force that animated line even when the output is captured;
- `plain` — one line per 10%, so logs and captured output show the stages too;
- `off` — no progress output at all.

### Measured phases

`python steam/steam_trace.py --restart --json steam/traces/steam-boot.json` samples the
process set every 100 ms across a real restart and records what actually happens. The
last run (`steam/traces/steam-boot.json`):

| Side | Observed sequence | Time |
|---|---|---|
| shutdown | helpers leave first | 1.32 s |
| shutdown | `steam.exe` alone, exiting | 0.33 s |
| shutdown | nothing left | 2.07 s |
| boot | `steam.exe` alone | 0.11 s |
| boot | `steam.exe` + `steamwebhelper.exe` | 2.08 s (settle window) |

Totals on that run: stop 3.75 s, boot 2.21 s. The bar's stop stage therefore reports
"helpers closed, client exiting" before the client goes, and the start stage reports
"client process up" → "helpers up (library loading)" → "process set settled". Those
labels are these measurements, not invented stages.

### When the tool considers Steam "back"

The client process is not the signal: measured here, `steam.exe` appears 0.02 s after
launch and its helpers 0.26 s later, but Steam's main window - title `Steam`, class
`SDL_app`, 1280x744, kept **hidden in the tray** - only exists after about 25 s. Waiting
on the process alone is what made the tool exit before Steam (and its tray notification)
was back.

So the wait is: client process → helpers → main window exists (hidden counts, because
Steam lives in the tray) → held for 2 s of grace. A live run reports:

```
+ 0.02s  client process up
+ 0.28s  helpers up (library loading)
+24.85s  Steam UI ready (window 1280x744, in the tray)
+27.01s  Steam is up: window and tray are back
```

If no window appears within 20 s the tool says so and continues rather than hanging.

## Files

| File | What it decides |
|---|---|
| `manifest.json` | library name, launch options, icon, sort name, tags, overlay/desktop/hidden flags, artwork mapping |
| `artwork/portrait.png` | library portrait capsule, 600×900 → `<appid>.png` |
| `artwork/wide.png` | library wide capsule, 920×430 → `<appid>p.png` |
| `artwork/hero.png` | library hero banner, 1920×620 → `<appid>_hero.png` |
| `artwork/logo.png` | transparent logo, 1000×300 → `<appid>_logo.png` |
| `artwork/icon.png` | shortcut icon, 256×256 → `<appid>_icon.png` |

## Where each one goes

- **Entry metadata** → `<Steam>/userdata/<account>/config/shortcuts.vdf`, one entry per
  shortcut. Field mapping is in `manifest.json` (`name`, `launch_options`, `icon`,
  `sortas`, `tags`, `overlay`, `desktop_config`, `hidden`).
- **Artwork** → `<Steam>/userdata/<account>/config/grid/`, renamed by the entry's app id.

`<appid>` is the id Steam computes for a non-Steam shortcut from its executable and name
(`steam/steam_shortcuts.py`, `shortcut_appid`). It is **machine specific**, which is why the
files here are named by role and renamed on install. On this machine the two entries are:

| Entry | App id | Artwork names |
|---|---|---|
| TerraForest | 3801998348 | `3801998348.png`, `3801998348p.png`, `3801998348_hero.png`, … |
| TerraForest Last World | 3967375980 | `3967375980.png`, `3967375980p.png`, `3967375980_hero.png`, … |

`config/grid/` does not exist until artwork is first set; Steam creates it on demand.

## Replacing the placeholders

Drop your own PNG in place, keeping the file name and the size in `artwork_sizes`. The
portrait capsule is the one that dominates the library grid; the hero and logo are what the
game page shows at the top.

## Caveats

- Artwork file names are a client convention, not a documented API.
- Artwork appears after Steam refreshes the library (sometimes a restart is needed).
- Metadata edits need the same stop-Steam → write → start cycle `commit()` already performs.
