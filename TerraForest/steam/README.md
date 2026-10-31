# Steam installation resources

Everything that decides how TerraForest appears in Steam lives here, so the choices are
visible and reviewable before anything touches `shortcuts.vdf` or the Steam grid folder.

The three tools live here too, next to the resources they apply. `manifest.json` and
`artwork/` are not read by the installer yet — they are the source of truth to wire up next.
The placeholders are real images at Steam's exact sizes, so replacing them is a drop-in.

## Tools

| Script | What it does |
|---|---|
| `install_to_steam.py` | copy the build, stamp the icon, register in Steam (`--last-world` adds the second entry) |
| `uninstall_from_steam.py` | remove both Steam entries in one pass, with backup and restart (`--list`, `--dry-run`, `--name`) |
| `add_desktop_shortcuts.py` | create or refresh the two desktop shortcuts, preferring the Steam launch when an entry matches |

All three are run from the project root, e.g. `python steam/install_to_steam.py --dry-run`.
The shared `shortcuts.vdf` engine stays in `tools/steam_shortcuts.py`.

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
(`tools/steam_shortcuts.py`, `shortcut_appid`). It is **machine specific**, which is why the
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
