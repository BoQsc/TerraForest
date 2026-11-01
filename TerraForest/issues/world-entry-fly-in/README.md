# World entry fly-in

- Status: Source verified; combined installed verification pending.
- Updated: 2026-11-01.
- User review: Enabled-by-default preference approved; motion and images not reviewed.
- Request: An optional three-second descent from above the world into the current player's first-person camera after world loading.

## Behavior

ESC → Player → **World entry fly-in (3 seconds)**. Enabled by default, saved in
`user://player_view.cfg` independently of world saves. The next ordinary world load
runs the entry after terrain, forest, buildings and physical spawn are ready.
Space skips; Escape ends the entry and opens the ordinary pause menu. Opening
inventory/map or losing focus also ends it. Indoor/cave and submerged spawns enter
directly. Enabling the setting mid-session takes effect at the next world load.
The entry ends in first person for that session; it does not erase a stored
third-person preference. Disable entry to retain that preference on every load.

A temporary camera renders the actual world and current player model. It never
moves the eye, body, saved position, physical focus, mouse or OS focus. World
interaction, player movement, survival and nearby actor simulation are suspended
for the entry. Near collision/ecology stay at the player; remote rendering uses
the existing overview path. The camera is freed and its processing stops afterward.
Tools/offscreen/temporary diagnostics opt out unless given `--entry-fly-in`.

## Verification / images

Source parser/import pass. Existing populated world: **24 checks pass**
([receipt](../../reports/checks/20261101T162215549658Z/run.json)). Ordinary browser
launch of a new owned Original woodland / seed 1703 world: **25 checks pass**,
without an entry diagnostic flag
([receipt](../../reports/checks/20261101T162329590648Z/run.json)). Checks cover
loading/spawn readiness, real viewport, whole-world visual coverage, unchanged body,
eye, save pose, physical focus and building residency; skip/Escape/focus loss;
roof fallback; persistent setting; restoration of first-person/third-person/overview.
The read-only populated fixture remains byte-identical. Sampled process memory and
VRAM stayed within project budgets. The existing renderer's LOD/performance limits
remain tracked in [world overview](../world-overview/README.md).

The first run failed its roof query and a focus assertion
([retained failed receipt](../../reports/checks/20261101T161505969845Z/run.json)).
The roof ray exceeded the native 256 m cap; two bounded segments fix it. The test
compared physical focus with the body's post-step position instead of its actual
initial focus. Corrected checks pass. Initial image inspection also rejected early
camera rotation that lost the character; the revised shoulder approach retains it.
Initial capture PNG writes stalled the animation under test; the recording fixture
now buffers screenshots for compression after the fly-in. These old capture timings
are not clean runtime performance measurements. Final buffered package recording
and installed verification remain required.

![Actual populated world from above](images/aerial.png)

Revised source, existing Exploration world / seed 1703, full terrain and forest.

![Player visible during final approach](images/approach.png)

Revised source, same saved player, before the head handoff. These screenshots were
inspected; user motion and visual approval remain pending.

![Rejected early rotation](images/rejected-early-turn.png)

Earlier rejected source: rotation lost the player. Preserved for comparison.
Capture provenance and hashes: [manifest](images/manifest.json).

The check is `tests/entry_fly_in.gd`. `--entry-slot=<owned-fixture>` opens it read-only;
`--entry-browser` exercises ordinary persistent browser launch with a new unique
owned slot. Its ready callback contains automation mouse ownership only after the
ordinary default preference/eligibility path has executed. It never changes real
camera preferences. New implementation and check are original AI-assisted 0BSD;
no imported art or code was added.

## Remaining / resume here

Coordinate the focused source commit with the active quest/clothing integration.
Then export a matching package, run the installed normal-browser check and capture
the buffered three-second motion. Do not overwrite concurrent work or install a
stale PCK. Source qualification is complete for the cases above; installed
qualification and user motion/visual approval remain separate.
