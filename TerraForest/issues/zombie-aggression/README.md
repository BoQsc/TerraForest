# Passive zombies and sleeper ambushes

- Status: Improved / scoped checks pass; gameplay balance review pending.
- Updated: 2026-11-04. Fix: native awareness, guarded waking and encounter tuning.
- User review: Not yet playtested by the user.
- Symptom: Sleepers ignored a silent nearby player, rose slowly and failed to commit; ordinary zombies could disregard attacks or an obvious close threat.

## Changes

Sleepers check a stationary player within 2.5 m using a ray from their actual
posed head. About 0.4 seconds of uninterrupted, ready, unobstructed sight triggers
waking; breaking sight clears caution. Noise and damage retain existing wake
paths. Proximity alone cannot wake sleepers through walls.

The authored rise plays at 1.65 times its previous rate. Clearance sampling,
collision checks, retry budgets, anatomical restrictions and physical/native
completion handshake remain authoritative. The shipped minimum wake timer is
1.1 seconds; the full physical rise still gates combat. At 60 Hz the close-approach
fixture completes seated/lying waking in approximately 2.4/3.0 seconds including
caution. Waking actors track only a player they can actually see, then enter chase
immediately after rising.

Sleepers use at least a 2.2 chase multiplier over their own ordinary walk speed.
Last-sighting memory lasts 35% longer (capped at 30 seconds) and local search 50%
longer (capped at 15 seconds). Authored identity retains this temperament after an
awake save/reload; the save format is unchanged.

Ordinary distant recognition, roaming and unprovoked pursuit budgets are retained.
Inside the existing 2.5–3 m near-sense range, confirmed visible recognition takes
0.2 seconds and chase speed uses at least a 1.8 multiplier. All accepted damage
paths provoke awareness. Retaliation checks behind the zombie and bypasses
recognition once sight is confirmed. Visible close threats interrupt disinterest.
Close threats, provocation and ambushes renew interest while sight persists.
After losing sight they retain only the last clue; unseen/search/blocked expiry
still permits escape.

## Images

![Generated house sleeper](images/sleeping-house.png)

Current source build, seed 1703, generated house upper floor, 1920×1080 Forward+.
Player held outside close sensing range for the sleep pose capture.

![The same resident after waking](images/awakened-house.png)

Same house, camera and settings after a test noise wakes the resident. Both images
were inspected. These establish supported poses in actual building geometry;
timing, targeting and damage come from regression traces. They are current
evidence, not a before/after AI comparison or player approval of animation feel.
[Image sources and hashes](images/manifest.json).

## Verification

[Compact evidence record](evidence.json), with links to retained local reports:

- Debug/release native builds, awareness and shipped-profile checks.
- Rendered aggression fixture: close/walled/unready sensing, interrupted caution,
  both rises, immediate targeting, physical attack damage, retaliation, memory
  expiry, cooldown and the existing two-probe perception budget.
- Existing sleeper runtime and fresh-process restoration: ceilings, bounded
  retries, supported reversal on leg loss, pause, death and completion handshake.
- Generated house creation, wake, awake reload, death persistence and hidden
  re-admission; actor-route and zombie navigation regressions.

Original code/tests were authored with OpenAI Codex from the maintainer's request
under 0BSD; tuning uses the existing original CC0 data. No external code,
animation or asset was imported for this fix.

The first new harness run lacked scene attachment because a one-line callback
captured the following statement; corrected before passing checks. Retained log:
`reports/checks/20261104T141527888746Z/`. The first generated-house admission
phase did not find its selected resident; the fresh-process retry passed with
that same selected identity. A proposed fallback to another resident was not
exercised and was removed. The initial failure's cause remains unqualified;
production admission and fixture selection are unchanged. Original failed phase:
`reports/house_sleepers/20261104T141821378613Z/admission/`.

## Remaining / resume here

Player review of outdoor encounters, house surprises and the ten-zombie coal-mine
station is needed to judge difficulty and persistence. Return on feedback that
sensing, rise speed, chase speed or memory is too weak/strong; tune explicit fields
in `addons/characters/runtime/assets/zombie.encounters.json` and repeat aggression,
sleeper safety and generated-house checks. Dense mine crowding and broader
navigation/performance acceptance retain the limits in
[the navigation standard](../../docs/NAVIGATION_STANDARD.md).
The transient house-admission failure should be revisited if it reproduces;
retain selected/admitted identities and loading/publication timing on the next
failure before attributing it to capacity or streaming.

The initial export found unsupported compressed WAV containers in the existing,
unintegrated `addons/audio_runtime/packs/Kaino/` source folder. This AI build
temporarily excluded that unused folder during export; originals remain intact.
Audio import/integration belongs to a separate task. No audio conversion or
playback behavior change is included here. Original export failure retained in
`reports/zombie_ai_import.log`; the final export log records success.

## Reproduce

`python tools/check_zombie_aggression.py` runs the source fixture; add
`--executable` after exporting matching DLLs/PCK. Use
`python tools/check_zombie_sleepers.py runtime` for physical safety/restoration.
The aggression fixture owns an isolated scene. The house checker creates a
`SleeperHomes_` save; user saves are left intact.
