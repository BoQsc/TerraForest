# Metropolis and inhabited region

User brief, 2026-11-27: a large city containing the three grand buildings, every
medium type and smaller buildings; at least two large bridges and one small
bridge; more lived-in locations across the map and better organization.

Choose **Create world → Starting recipe → Metropolis & inhabited region**.
Seed **1703** is the verified source planning/contact case. New source worlds
use the [long-lake profile](EXTENSIVE_LAKES.md), with three 360–480 m lakes. This is an additional
recipe; the existing default and saved recipe formats remain available. The
installed export has not been rebuilt for this work.

## Layout and guarantees

The city has three named twelve-building quarters: Cathedral & civic, Foundry &
apartment, and Needle Street & manor. They include Foundry Court, Saint Brigid,
Needle Street, Homestead Manor, all six city and five civic types, both shops,
large houses, workshops, two/three/four-storey towers and smaller cottages. Six
eight-building communities bring the total to **84 buildings**, before normal
lookouts and exploration locations. The preview also includes two lookouts.

Each city quarter fits four street blocks; each village fits two four-building
frontages. Their widths come from actual prefab bounds. Blocks can turn and
relocate within bounded searches instead of forcing every building onto one
large flat grid. The city anchor follows gentle terrain; corner cities can grow
along both shores, keeping their civic quarter between residential quarters.
The six outlying hints rotate with that anchor and include a central community.

A candidate must connect to the accepted streets before placement is accepted.
The regional planner recognizes those existing surface connections instead of
laying another spanning network over them. Grade-separated crossings remain
separate. The three grand buildings and all communities receive named map
places. City-quarter centers remain within 750 m of the civic quarter.

Publication planning requires two **32–96 m** bridges and a separate **12–28 m**
bridge, each connected at both banks. The current long-lake profile-33 case has
**32 m and 32 m lake bridges** and a **24 m small lake crossing**. The earlier
profile-29 case had 52 m / 40 m lake bridges and a 28 m seasonal-gully footbridge.
That older small crossing spans a real depression. Neither case fabricates water
or fills the middle of a bridge. The new recipe uses
continuous timber decks over their beams and abutments, with the same native
exposed-surface clearance used for buildings. Older bridge designs retain their
original deck geometry.

The 100 m regional grid reports **75.6% within 400 m of a community or quarter center**, with
a maximum of **735.0 m**. Its hard maximum is 750 m. This distribution measure
includes intentional natural gaps; it does not establish ground-level design
quality. Other seeds can fail their bounded survey. Required buildings or
bridges are never silently omitted to produce a passing preview.

## Terrain, persistence and work bounds

Surface grading limits remain **2 m fill / 3 m cut**, including occupied floors,
aprons and approaches. City frontages reserve the full road support/shoulder
and lattice transition. Deep buildings use actual buried masonry roots beneath
low wall/stair columns that otherwise depended on isolated soil pedestals. These
are additional editable cells in the generation variant; the authored source
cells and attachments are retained. Original catalog assets are not rewritten.
Resident admission independently proves that every original cell and model is
unchanged and that additions are masonry below original low support columns.
The cathedral's cross-shaped crypt has a separate, explicitly bounded deeper
interior excavation before final native
surface clearance. There is no whole-city plateau or terrain repair on load.

Native curve optimization now bounds the complete Hermite correction, including
its interior controls, within the existing 0.55 m displacement cap. The original
final grade, curvature, cut/fill and protected-entrance checks remain in place.
The native regional network still accepts at most nine district nodes. Cell and
active-object budgets are unchanged; large bridge spans and the deep cellar band
are explicit additional design cases. The temporary developer
storage allowance is recorded below.

The native room-light survey visits authored support cells instead of empty
bounding-volume columns. Large apartment buildings use explicit 128-room pages;
each native page retains the 200,000-probe cap and generation reads every page.
The existing 2,048-light world limit and four active rendered lights remain.
This cold authoring work does not add a per-frame room scan.

The durable profile is recipe v8 (44 bytes); earlier 28/32/36/40-byte snapshots
retain their formats. Plan v56 includes the new profile/content identity and
omits exploration/lookout worker timings from the serialized geometry digest.
Independent builds therefore have the same identity, including under concurrent
preview requests. Existing saved worlds are not regenerated.

## Profile-29 baseline evidence and remaining work

- `reports/checks/20261127T133018334105Z`: **297 source checks passed**, including
  all 84 buildings, all nine sidewalk sets, all three bridge exposed surfaces
  and deep end supports, normal browser preview, named landmarks, exact cache
  hydration and a second independent native rebuild with the same digest.
  This final run also covers restored attachments, reviewed-resident admission
  and complete bounded room-light paging. The earlier 247-check passes remain.
- `reports/checks/20261127T120856720088Z`: 11 focused checks for existing street
  components, overpasses, actual cubic crossing heights and dense curve bounds.
- `reports/checks/20261127T123059450275Z`: shared terrain/block contract passed.
  `20261127T123059439113Z`: twelve legacy terrain profiles/seeds retain exact
  height/material bytes. `20261127T123059466083Z`: existing recipe translation
  and 42 production-catalog `--recipes-only` assertions passed. The retained
  full headless catalog run `20261127T125310436517Z` passed its 40 assertions but
  failed its DummyTexture/ObjectDB exit gate; it is not a passing full export gate.
- Release recipe codec: 29 checks passed. Release connected-road checks also
  passed, including three-lane physical collision sampling. Final native receipts
  and exact binary hashes remain in the standard reports.

Rejected evidence remains available: the oversized rectangular quarter
(`20261127T110644789761Z`), unsupported final foundations (`20261127T122043833788Z`),
and original bridge surface contacts (`20261127T123300728225Z`). An initial
concurrent preview exposed elapsed worker times in the geometry identity;
`20261127T124249177685Z` records that failure. These are not passing site evidence.
Cold-retained images remain recoverable from their owning archive manifests.

The first ordinary generation attempt (`reports/metropolis_world/20261127T125624633543Z`)
rejected footing variants because rebuilding their cells had cleared attached
models. Generation now restores those exact attachments, with regression checks
that reject unrelated masonry and changed room fabric. The second attempt
(`20261127T131430159150Z`) exposed the large-room survey limit, addressed by sparse
floor enumeration and bounded paging. Both failed staging worlds were verified
and cold-retired through their own `world.archive.json`; player saves were not
selected. The catalog failure `reports/checks/20261127T132259636510Z` additionally
retains the two apartment buildings' original 128-room overflow.

`reports/metropolis_world/20261127T133016071394Z` passed ordinary creation,
publication, exact saved E2 geometry and normal trading. Its later camera
inspection failed NPC persistence after the inherited helper suspended the world
physics callback across teleports, leaving resident bodies without their normal
streaming owner. The production test now keeps zombie and actor residency updates
active while its player controller is suspended. This run is retained as failed;
its owned staging/published files were verified and archived (67,906,592 bytes).

The later publication `20261127T134014073064Z` is reused for inspection retries.
The first inspection requested collision for an entire cathedral at once, beyond
the ordinary 48 m local collision radius. The corrected check requests local
entrance collision and independently compares every saved landmark cell, without
raising that radius. The `recheck_metropolis_world.py` launcher requires the
original passed creation/native hashes, allocates no new world, preserves earlier
receipts and image groups, and retires the same fixture only after successful
interaction/restoration. A zero-reference ObjectDB warning from an earlier exit
remains recorded; the harness now drains deferred releases before quitting.

The focused structures DLLs are built from committed native inputs plus the three
room-planner source changes, excluding the separate uncommitted renderer trial.
`reports/metropolis_clean_native.json` records both exact DLL hashes and ten
passing room-API assertions per target. Full world checks separately record the
actual working native hashes. No installed pack or full source copy was built.

**Normal Generate & play publication, trader interaction and fresh-process save
restoration pass in source.** `reports/metropolis_world/20261127T134014073064Z/recheck.json`
records the original six-check creation phase, the 66-check interaction phase
and a 23-check fresh restoration, all passing. The final restoration reuses the
passed interaction only after matching its exact test and native hashes; earlier
failed receipts stay in their own capture groups. `world.archive.json` and
`recheck_retention.json` verify retirement of **68,116,532 bytes** from that exact
new staging/published fixture. No player save was selected.

The
`tools/check_metropolis_world.py` uses the ordinary production test with no
review switches, declares 160 MiB of reports and a 224 MiB peak owned-world
allocation, and archives its exact new fixture after process exit. The user
explicitly approved temporary QA headroom on 2026-11-27. `--approved-headroom`
adds 256 MiB each for reports and owned worlds in that Python process only;
repository limits are unchanged and normal limits resume at process exit.
`tools/recheck_metropolis_world.py <report> --restore-only` can reuse a matching
passed interaction while its fixture remains ready. Cold-retired fixtures are
never silently recreated under the old identity.

Some earlier processes passed every gameplay/save assertion but reported one
zero-reference ObjectDB survivor at engine exit. A later identical-driver restore
exited cleanly. This is **intermittent exit-cleanup behavior, not a universally
resolved lifetime bug**; verbose diagnostics and the failed gates remain retained.
Return trigger: an engine/native lifetime investigation. Closure requires repeatable
clean exits, including the full headless catalog gate, before export qualification.

The inspected map, creation screen, three generated landmark overviews, deep
crypt and three bridge views are layout evidence. The city follows gentle shores
and still has green intervals between quarters. Full street/threshold/interior/
crypt/bridge walks and user visual approval remain unaccepted. Some landmark
captures show sub-60 FPS HUD values; these uncontrolled frames do not qualify
sustained populated-world performance. Do not promote this source recipe into a
finished world-quality or installed-build claim.

Post-verification retention is recorded in `reports/metropolis_final_retention.json`.
Besides the owned world, verified cold archives hold **163,868,044 bytes** of the
focused native scratch build and **137,430,473 bytes** of remaining QA captures.
The owning manifests are `reports/metropolis_clean_native.archive.json` and the
production report's `all_captures.archive.json`. Logs, completion receipts and
selected versioned issue images remain ready. Image provenance identifies its
own archive; cold evidence is recoverable rather than discarded.

## Long-lake source update

Profiles 32–35 add three substantially longer lakes. The source profile-33 case
has two **32 m** lake crossings and a **24 m** small lake crossing; all required
building types, 84 buildings and six outlying communities remain present. Adjacent
city quarters now share 119 identical sidewalk cells under one owner, leaving
6,616 unique destructible paving cells. Different blocks at the same coordinate
reject instead of overwriting. Final contact and combined publication checks pass.

The new evidence and remaining quality/exit gates are recorded in
[Extensive lakes](EXTENSIVE_LAKES.md). Older installed/profile-29 images and
performance limitations above remain historical evidence, not long-lake approval.
