# Resource gain notifications

2026-10-24. Small lower-right rows show the existing item icon, `Gained <name>`
and a green `+amount`. Repeated gains merge by item; up to five rows remain for
three seconds, with a short fade. Five controls are reused, shared atlas icons
are retained, and processing stops when empty. The overlay ignores mouse input.

The existing HUD refresh compares confirmed inventory totals, including worn
clothing. Slot rearrangement, equipping clothing, changing bucket fill state,
startup items and saved-inventory restoration do not count as gains. Loading,
offscreen generation/capture, development and session-menu states stay quiet.
Mining overflow appears only when it actually reaches carried inventory. The
display does not mutate inventory, receipts, crafting or storage.

Thirteen real-world assertions pass in both source and exported PCK/dist:

- `20261024T092314806430Z`: actual E pickups, merged counts, slot rearrangement,
  native mining/publication, crafted brick icon, restore suppression, clothing
  transfer suppression, lower-right bounds and timed fade/idle processing.
- `20261024T092534656505Z_resource_gain_feed_pack`: the same assertions with
  game resources and native libraries resolved from the exported build. The
  external assertion helper and PCK/engine/library hashes are in its manifest.

`gains.png` was inspected at 1920×1080: readable icons/names/amounts, five small
rows clear of the centered toolbelt and crosshair. `export.log` and
`pack_smoke.log` record normal startup with fourteen external native libraries.
There were no failed runs for this change. This is presentation verification,
not a new aggregate frame-performance benchmark.

Reproduce with `python tools/run_godot_check.py resource_gain_feed --timeout 100
--require 'failures=0' -- --gameplay-construction --no-zombies`. After export
completes, `python docs/evidence/resource_gain_feed/check_pack.py` runs the
packaged check. The fixtures use a temporary world.
