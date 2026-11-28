# Inhabited island — first human playtest

Status: first recipe implemented and functionally verified, 2026-11-28; human
review pending. Strict QA still rejects a shutdown reference warning. Existing
saves and the Metropolis recipe retain their own identities.

The user supplied a regional survey image and a design description on
2026-11-28. They describe an inhabited island after a zombie apocalypse, with
geography determining water, transport, settlements and infrastructure. The
image is a design reference, not a fixed layout to copy. The first playtest
scope was explicitly chosen as geography, settlement hierarchy and connected
routes using existing buildings. Missing infrastructure follows that review.
The source attachments remain in the chat; no reference bitmap is imported into
the game. The user declared the original design/artwork CC0-1.0 to the extent
of rights held. New original implementation and tests are 0BSD; existing prefab
terms and provenance remain unchanged.

## Separate recipe and native geography

The ordinary creation menu gains **Inhabited island · first playtest**. Its
native RCP1 recipe is version 9, profile 2, with immutable terrain generator 36.
Earlier recipe bytes and terrain fields remain supported. JSON remains an
authoring/inspection view; runtime generation and restoration use binary bytes.

The new native terrain field has broad lowlands, three asymmetric seeded ridges,
an irregular coast around all four boundaries and the existing physically
sampled long-lake system. Ridge parameters are derived once per field. It does
not flatten one pad for a city. Individual streets, foundations and entrances
still obey the existing 2 m fill / 3 m cut limits. Continuous river drainage,
streams and wetlands from the wider reference remain outstanding; long lakes
must not be described as a completed river system.

Native district composition reuses existing authored buildings:

| Role | Count | Buildings |
| --- | ---: | ---: |
| Main city quarters | 3 | 36 total, including all three grand buildings |
| Separate towns | 2 | 16 each, with coastal-storage and industrial themes |
| Smaller communities | 4 | 4 each |

Two towns must remain at least 900 m apart after fitting. City quarters remain
connected within the current 750 m coherence bound. Seeded preferences change
with geography and fitting may relocate or reject a site. Titles alone do not
establish a functioning harbor or farm. The first layout retains 84 settlement
buildings plus the existing separately fitted wilderness lookouts.

The ordinary transport planner must connect the fitted street network, preserve
alternative routes where terrain permits, and fit at least two large bridges
and one small crossing with usable approaches on both banks. New road grading
must never relax terrain/contact rules just to admit a seed.

## Verification and human review

Component checks pass native recipe corruption rejection, old recipe
compatibility, twelve byte-identical legacy terrain lattices, seeded hierarchy
variation, all-side sea boundaries and composition counts. The complete fitted
layout for seed 1703 takes 2.929 s; its town centers are about 1,873 m apart.
That is one fitted seed, not broad-seed quality acceptance. Evidence:
`reports/checks/20261128T111302609383Z` (53 checks),
`reports/checks/20261128T111415728554Z` (29 fitting checks), and
`reports/checks/20261128T113605074855Z` (53 checks using the committed legacy fixture).
The ordinary preview path also passes 55 checks in
`reports/checks/20261128T114146199862Z`; its retained 256-square image was inspected
and shows the same draft shoreline, lakes and settlement arrangement. Python
inspector checks pass nine cases, including the version-9 recipe and rejection
of mismatched profiles/introduction; eight retention checks preserve the human
save boundary.

Normal UI creation, interaction and fresh-process restoration pass 6 + 73 + 30
functional assertions in
`reports/inhabited_island_world/20261128T112502004352Z`. The generated save has
86 buildings, the three grand buildings, two large bridges and one small bridge.
The create process exits cleanly; interaction and restoration each retain the
known zero-reference ObjectDB shutdown warning. **Strict QA fails.** Diagnostic
continuation does not waive that gate. The native debug/release libraries match
their current sources; initial Zig/LLD FileNotFound build attempts and successful
retries with compiler verbosity enabled remain in the bounded build logs.

The successful functional fixture, `Island_1703_b743c970`, is protected for the
requested human playtest. `tools/launch_recipe_playtest.py` validates its receipt
and native hashes before opening that existing save. The approved temporary
256 MiB report and 256 MiB world allowances ended with QA; normal limits and
archive capacity are unchanged. No release/export or visual acceptance is claimed.

The human review should assess whether the city reads as one place, towns feel
distinct and distant, countryside is meaningful, mountain/coastal transitions
look natural, and roads/bridges meet real destinations. Inspect the overview and
ground views; automated checks do not establish visual acceptance. A supplied
playtest save becomes user-owned and is not automatically retired as QA output.

The certified saved-map overview was decoded with checksum validation and
inspected (`certified_map.png` and `map_decode.json` in the QA receipt). It shows
a nearly square coast, straight narrow long lakes and separated street clusters.
Those features do not yet meet the reference's natural coastline/waterway or
urban-form quality. Ground-level and human review remain pending; the map is a
captioned diagnostic of this draft, not an accepted visual comparison.

After that first recipe milestone, continue cold route planning, scene
initialization and first-play loading. The complete cold Generate-to-play timer
must include planning, all content, durable publication and readiness for player
control. The target is below 30 seconds; cached planning, missing content or
work moved after the timer cannot qualify it. The current performance contract
and failed exit-warning gate remain in [NATIVE_GENERATION.md](NATIVE_GENERATION.md).

This island's first complete cold-plan Generate-to-play measures **80.142 s**:
49.771 s generation, 24.569 s first-play loading, plus scene handoff and
publication. Cold plan compilation itself is 7.120 s. The largest measured
stages are generation scene/terrain initialization (19.686 s), first-play
landscape coverage (12.873 s) and first-play map preparation (8.530 s).
They identify the next profiling targets; they do not prove individual CPU
costs or a same-content speedup over the older Metropolis measurements. The
timer still fails the 30-second target. Work must not move beyond readiness
or drop content to make that timer pass.

## Outstanding design work

Harbors/docks, railway/stations/yards, airstrip, major utilities, additional
public services and agricultural fields require geography-aware composition
and playable assets. Do not label an existing warehouse as completion of these
systems. Continuous waterways and more varied local street forms remain open.
Return to these after the first human geography/layout review; closure requires
ordinary generated placement, usable connections, persistence and inspected
ground-level evidence. The first playtest does not close the full design vision.

Build/check admission and bounded artifact lifecycle are recorded under
`reports/inhabited_island_20261128/`. No new worktree or export is required.
