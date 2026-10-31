# Brand

The single source for how TerraForest presents itself: identity, palette, and the artwork
Steam shows for the library entry. `steam/` consumes this folder; nothing here talks to
Steam directly.

## Files

| File | What it holds |
|---|---|
| `brand.json` | name, tagline, description, studio, palette, and the Steam genres/tags plus the artwork sizes and Steam target names |
| `make_brand_artwork.py` | draws every artwork size from `brand.json`, stdlib only, deterministic |
| `../artwork/` | the generated PNGs the installer will copy into Steam's grid folder |

## Regenerating the artwork

```
python steam/brand/make_brand_artwork.py            # rewrite steam/artwork/
python steam/brand/make_brand_artwork.py --out DIR  # write somewhere else
python steam/brand/make_brand_artwork.py --check    # fail if steam/artwork/ is out of date
```

`--check` is the useful one for commits and CI: it renders in memory and compares bytes, so
a hand-edited PNG or a stale artwork set fails loudly instead of drifting.

## How the artwork is composed

One geometry serves every size, scaled to the requested pixels:

- background: vertical gradient from `background` to `accent_deep`
- sun: a disc in `sun`
- conifer: a trunk and three tiers in the `foliage` ramp (deliberately separate from the
  ground, so the tree never disappears into the hills)
- ground: soft arcs in the `terraces` ramp, lighter towards the front
- logo and icon: no background (logo is transparent), so they sit on Steam's own tiles

Nothing is random, and no external fonts or images are used, so the same `brand.json`
always yields the same bytes.

## Metadata

`steam/manifest.json` carries what the installer writes into `shortcuts.vdf` (names,
launch options, icon, sort name, tags, overlay flags). The brand is authoritative for the
values they share: name, tags and artwork sizes. The test suite compares the two files, so
they cannot drift apart silently.

## Not done yet

- The artwork placeholders are drawn from code, not an art pass.
- `steam/manifest.json` and `install_to_steam.py` do not read `brand.json` at runtime; the
  values are kept in sync by the checks, and wiring them up is the next step.
