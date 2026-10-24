## Carried terrain, repair hammer and vehicle actions - 2026-10-24

Mined topsoil, stone and ores now place paid native terrain samples with right
mouse. One carried unit creates one recoverable sample; occupied stamps refund
through the saved native inbox. Neighboring solid material is preserved. Item 3
keeps its saved identity and is now the repair hammer: left mouse attacks, right
mouse repairs damaged blocks/objects/vehicles at animation contact. It no longer
selects construction controls. Session offers a saved, optional targeting outline
for every held tool/weapon. Building materials retain their own placement controls.

ESC / Developer lists searchable physical item pickups and an actual vehicle
spawn action; free spawning requires development mode. Vehicle item 501 uses the
ordinary native inventory, dropped-stack and container formats, preserving
structural damage through pickup/storage/deployment. Tap E retains entry; hold E
opens Enter / Pick up actions with live identity/range/occlusion checks. E exits
at any speed when an exit capsule fits in loaded space. Unoccupied vehicles keep
physics/momentum, remain resident while coasting and park once grounded/stopped.

Debug/release builds, native conservation/save checks, real input/UI/vehicle
integration, package runtime and grass continuity pass. Retained failures,
reproduction and inspected captures: [item integration evidence](evidence/gameplay_item_integration/README.md).
This closes the requested interaction implementation. It does not qualify total
frame cost, large-scale terraforming, vehicle cosmetic-dent persistence or final
interaction feel. Existing dents were already transient; structural durability is
preserved. Revisit balance/hold duration on play feedback and measure combined
travel/streaming/coasting costs before performance acceptance. Existing world
quality and navigation requirements below remain open.

## Grass continuity during placement and mining - 2026-10-24

The recurring edit-triggered grass blink had a separate native path from the
earlier single-pickup correction. Bulk exclusions, support-transform updates and
insertions discarded affected visible pages, then waited for budgeted uploads.
Faded ground-cover collections now compact local membership and refresh changed
resident pages within the edit call. Insertions retain old partial pages while
new payload is admitted; unchanged plants retain both transforms and fade ages.
The immediate work scales with touched resident pages/local groups and remains
separate from the background upload budget. Resident byte/page ceilings remain.

Native debug/release regressions, actual paid brick/native mining and per-rendered-
frame packet checks, retained failures and exported-runtime evidence are in
[edit continuity evidence](evidence/vegetation_edit_continuity/README.md). Explicit
restore retains its original rebuild semantics. Existing pickup/fade, streaming,
tree-support and generic-model checks pass. These checks close the reproduced
local edit path; distant travel, other shadow/shimmer causes, combined budgets
and sustained frame-cost qualification remain open below. If playtesting exposes
another blink, preserve its trigger and first failing frame against these witnesses
instead of treating post-settle membership as continuity proof.

## Zombie roaming, awareness and distant admission - 2026-10-24

The existing session spawner now waits eighteen active-play seconds after startup
or pose/world restore, admits outside the player camera at 40–64 metres, and
attempts one admission per eight-second interval. Collision, water, occupancy and
the six-controller cap still apply. Native awareness supplies randomized wandering,
sight acquisition, pursuit, last-seen investigation, a short local search and
loss of interest. Hidden movement cannot update the remembered destination.
Unreachable pursuit has a cooldown. Wandering/searching never supplies a player
attack recipient; existing authored contact and native route/motor owners remain.

Native debug/release, physical behavior, real-world distant admission and existing
navigation/combat verification are retained in [awareness evidence](evidence/zombie_awareness/README.md).
Human acceptance of pacing and encounter density remains open for play feedback;
revisit the declared ranges/timers against actual travel and surprise encounters
when that feedback arrives. Encounters are still bounded and session-local.
Saved population/loot, player health/death, automatic traversal links and sustained
population/frame-cost qualification remain the explicit requirements below.

## Held-tool impact timing - 2026-10-24

Gameplay hits now resolve at the actual held animation's contact pose, with one
live reach/occlusion query, native damage, feedback and wear per swing. Recovery
gates held-input repetition. Equipment, menus, inventory, Alt controls, focus loss
and world reload cancel pending strikes; native ownership is checked at contact.
The approved pickaxe animation keys and existing native stores/save formats are
unchanged. Empty hands use the existing relaxed hand-reach clip; a newly authored
punch is not part of this timing change.

Source and exported-runtime verification and inspected contact captures are
recorded in [attack timing evidence](evidence/attack_animation_sync/README.md).
Engineering checks cover contact/recovery/cancellation and existing damage/wear
routes. Human acceptance of strike feel remains open for play feedback; revisit
the contact profiles against the actual held meshes if that feedback identifies
a mismatch. This does not close the generator, storage, mining-latency or world
performance requirements below.

## Session menu and contextual tool controls - 2026-10-24

Escape now opens Session and Destinations consistently. Toolbelt duplication and
editor categories have moved out of that menu. Hold Alt to use the selected
tool's quick controls; detailed construction/object/road settings open their own
scrollable workspace above the belt. World tools owns diagnostics, vehicle and
water authoring, while Actors owns actor/resident controls. Closing settings
returns to aiming; another Escape opens Session. Gameplay retains owned-item and
cost checks. Existing input, save/native ownership and original tool capabilities
are retained, including both box-brush variants.

The 34-check belt/focus regression, 34-check player/save smoke, 51-check combined
interaction, 6-check object accessibility and 17-check actual water-action checks
pass. Relevant fullscreen 1920x1080 captures were inspected. Failed implementation
and outdated-fixture runs remain in [tool-menu evidence](evidence/tool_context_menu/README.md).
The controls guide and runtime hints now name Alt/tool settings and ESC/session.
Human usability acceptance remains open until reviewed; follow up on that feedback
with the same actual tool/input routes. This requested UI work does not complete
or replace the generator/storage/mining/performance requirements below.

## Optional generated world names - 2026-10-23

Blank or whitespace-only names in Create world now receive a random two-word name,
such as Misty_Grove. The assigned name appears in the field and is passed unchanged
to generation. Existing save/backup/model/lock names are avoided, including case
aliases; a numeric suffix resolves collisions. Typed names retain existing
validation. Naming uses its own RNG and does not change the terrain seed. The
short browser policy/create-action check passes; see
[automatic naming evidence](evidence/world_names/README.md).

## Default gameplay tool selection - 2026-10-23

When gameplay becomes ready after startup/reload, an unselected toolbelt equips
its first owned tool in belt order. Returning from development mode does the same
if there is no previous gameplay selection. Explicit empty-slot selections and
other existing selections remain intact. The scan checks at most ten slots at
these transitions, never each gameplay frame, and never moves or creates items.
The actual HUD interaction/pose-restore check passes; see
[default tool evidence](evidence/toolbelt_default/README.md).

## Target durability feedback - 2026-10-23

Accepted gameplay attacks now show the target's name, remaining/maximum durability
and a colored bar beside the crosshair. Repeated hits refresh a 2.2-second display;
it fades and stops processing while idle. Inventory clears it immediately, and
menu/development focus suppresses it. Existing damage results supply the values;
there are no new world queries or health polling. Character hits show the struck
region's health. Actual-world attack and character checks pass (73 and 19 checks),
with block/object screenshots inspected at 1920x1080. Earlier failed setup and UI
checks remain documented in [target durability evidence](evidence/target_durability/README.md).
This is interaction presentation, not closure of world or performance gaps below.

Follow-up: fatal hits now hide this display synchronously rather than showing a
zero bar. Shared balance definitions and the initial [durability table](DURABILITY_TABLE.md)
cover every registered model, block material, cover species, terrain/entity class
and durable tool without changing maxima or save formats. Standalone character
anatomy keeps its own authoritative definitions. The table explicitly records
unsupported damage coverage and provisional values; listing them does not complete
player health, independent paving damage or material-specific terrain hardness.
See [catalog and destruction evidence](evidence/durability_catalog/README.md).

## Loading presentation and visible generation work - 2026-10-23

Generation and gameplay loading now share a wide, shallow bottom-centered progress
bar with smaller text and an overall percentage. The percentage is a stage-weighted
completion estimate using real counters where available, not an elapsed-time or
remaining-time prediction. Generation reserves verification/publication and the
final playable load: its child finishes at 88%, publication hands off at 94%, and
only the existing terrain/collision/object/water readiness gates unlock play at
100%. Ordinary saved-world loading starts at 0%. Cancel/error states stay explicit.

The follow-up adds centered gold/green TerraForest lettering and a default-on,
scrollable developer panel covering available native progress, raw queues/cache,
addon readiness, stage timings, world paths and coordinator results. Landscape
loading now exposes the actual required coverage fraction and worker/queue/cache
counters directly in the bottom bar; nearby-first coverage counts only its existing
384 m admission region. Diagnostics stop polling when gameplay starts. Targeted
rendered and actual generation/fresh-process reopening checks pass; see
[developer loading evidence](evidence/loading_developer_details/README.md). This
improves visibility; it does not close the loading latency or world-quality gaps.

The loading bar now shows elapsed time and an approximate remaining-time estimate.
Elapsed time carries from browser creation through the generator/coordinator to
the first playable load; later reloads start fresh. The estimate uses recent
measured progress, initially says estimating, and withdraws a stale prediction
while work is stalled. Completion freezes the total. This is a rough prediction
from weighted work, not a measured guarantee for every upcoming stage. See
[loading timer evidence](evidence/loading_timers/README.md).

Compact loading remains the default: a centered 1120-pixel progress panel at
1920x1080. The inline Compact switch has been removed at the user's request;
the optional width preference remains in loading_presentation.cfg. Timers and
technical details remain available. Earlier width verification is retained in
[compact loading evidence](evidence/loading_compact/README.md).

Generation and gameplay loading now share the same 50% dim overlay behind their
UI. Captures preserve the full rendered 1920x1080 lossless PNG, replacing the
previous forced 1280x720 reduction followed by upscaling. Display uses explicit
linear filtering at native size. Existing lower-resolution sidecars need the
read-only Refresh photographs action; they are not sharpened by upscaling. Actual
refresh, fresh generation/publication and reopening evidence is retained in
[loading photograph quality](evidence/loading_photo_quality/README.md). This is
presentation fidelity, not approval of the existing world art or a performance
qualification. World data and gameplay rendering settings remain unchanged.

Each photograph now names its viewpoint and exposes destination terrain/collision,
water, nearby vegetation readiness, then capture/save. Map preparation reports
pending layers, saved-world identity verification and cache writes. The first
instrumented three-view check spent 10.543 s loading destinations, 18.349 s waiting
for vegetation and 1.194 s capturing/saving images. These are finite observations,
not performance qualification. Photograph latency remains to improve alongside
streaming/vegetation admission: compare per-view timings and equal visual readiness
before closing it; hiding incomplete vegetation or dropping views is not a fix.

Evidence and final visual review: [loading progress](evidence/loading_progress/README.md).
This completes the requested UI presentation scope, not the larger generator,
storage, mining or generated-world quality requirements below.

## Bounded unpublished terrain generation integrated - 2026-10-23

Production generation now checkpoints its native earthworks inside the isolated
staging world before a compound root exists, then continues through bounded
residency. It no longer depends on keeping every authored sample resident until
the first complete-world save. Captures retain the exact private checkpoint
lineage; only verified outer publication selects the complete world. Existing
storage and nonpristine worlds reject before staging changes. Cancellation and
failed first outer publication retain safe retry/no-publication behavior.

Evidence: [generation staging](evidence/terrain_generation_staging/README.md).
The actual coastal plans for seeds 0/42/1703 serialize exactly like ordinary edits
under a 512-page bound. One native job authors 16,896 pages with 1,024 resident
pages and reopens with 32. The actual connected-world Generate → Load → Play
workflow and fresh full-game/cache reopen pass. These are separate finite scopes:
the rendered world has 479 authored pages, not the synthetic capacity workload.

This closes the previously missing unpublished-checkpoint generation mechanism.
It does not close populated travel beyond the former cap, long unsaved gameplay
pressure, mining arrival, retention/compaction, POI/options coverage, compute
benefit, visual world acceptance or thermal qualification. Private cancelled and
superseded products remain retained until ownership-aware collection exists.
Live command/checkpoint UI progress and finite mid-bake interruption cases now
have [generation lifecycle evidence](evidence/generation_lifecycle/README.md).
Planning runs on a worker while the loading screen remains active; native baking
starts after that screen is ready and publishes coherent counters without the
terrain lock. A native product-publication interruption and termination of the
actual Windows generator child retain valid private prefixes, publish no partial
world and permit verified regeneration under the same public name with a fresh
staging owner. Source and exported generation/reopen pass, with all four map
layers hitting cache and canonical bytes unchanged on read-only reopen.
These cases close the missing live progress and safe-regeneration evidence,
not physical power-loss/disk-full coverage or partial-bake resume. Retained
private products still need ownership-aware collection; broader storage failure,
capacity/runtime and world-quality gates remain open.
Keep every remaining requirement in WORLD_WORKFLOW_REDESIGN.md active.

## Selective native terrain residency integrated - 2026-10-23

Ordinary regional world loading now mounts the checkpoint directly instead of
expanding every edited sample. Exact saved pages fault through the native terrain
worker into a bounded LRU; unsaved pages and atomic edit footprints stay pinned.
The 16,384 resident-page ceiling is unchanged while the authored catalog can exceed
it. The capacity check reaches 16,896 pages with 1,024 resident pages, then cold
reopens with 32. Exact meshes, density/normal queries, incremental publication,
newer-edit pinning, damaged dependency rejection and allocation rollback pass.
Actual generated-world playback uses paging and hits all four baked map layers.
See [evidence/terrain_residency](evidence/terrain_residency/README.md) and
[the remaining storage contract](TERRAIN_REGIONAL_STORAGE.md).

This supersedes older statements below that ordinary loading still fully expands
regional terrain. It does not close mining response, whole-world memory or runtime
qualification. Demand faults run synchronously on the worker; targeted prefetch,
rendered populated travel beyond the old history cap, unsaved-edit pressure,
retention-safe collection/compaction and the failed first-visible mining gate
remain required. Finish those with explicit reader/checkpoint ownership, crash and
corruption recovery, exact distant representations, rendered travel and latency
evidence. Generator options/POI coverage, world visual quality and compute/thermal
qualification remain open; do not return to water flow or unrelated gameplay work.

The generated-checkpoint held-mining rerun explicitly still fails: first burst
capture-to-draw p95 about 272 ms, second about 73 ms, and both visible-gap gates
fail despite frame p99 below 20 ms. The older generator-1 fixture is a different
world, so this is not a controlled regression comparison. The follow-through
worker trace identifies repeated reconstruction of the still-visible 256 m owner;
native replay has no page faults during those expensive builds. Timestamped native
simplifier scratch removes nested neighbor/dedup searches with 60 byte-identical
pre-change mesh cases, but the new actual-world first-burst p95 is still 211 ms
and its maximum visible gap 284 ms. Both gap gates remain failed. See
[terrain_simplifier_links](evidence/terrain_simplifier_links/README.md).
Arrival needs bounded local owner replacement, preserving distant representation,
joins and collision, then the unchanged 150 ms response/gap gates. Prefetch remains
required for cold-storage admission; it cannot resolve the measured whole-parent
rebuild. The optional regional renderer is not automatically production-qualified.

## Block placement forest exclusion corrected - 2026-10-23

The reported Character Preview / slot-5 brick disappearance was reproduced in the
main scene: one brick outside all solid trunks removed three trees and their
shadows because construction used wind-expanded canopy boxes. Structure exclusion
now shares the native trunk proxy's solid bounds; rendering bounds stay independent.
The actual paid/right-click route retains all 2,724 trees and 3,179 tree/shadow
MultiMesh records, with no canopy revision or forest rebuild. True trunk overlap
and frontage undo/redo/restore checks pass. Images were inspected; the failing
reproduction and initial diagnostic timeout remain recorded in
[evidence/block_forest_exclusion](evidence/block_forest_exclusion/README.md).
This closes the reproduced canopy-exclusion defect, not the broader unfinished
generator, terrain residency, mining latency or populated-runtime requirements below.

## User-directed generation workflow correction - 2026-10-23

The ordinary Generate → Load → Play path now uses one generation child, native
binary verification and root-last publication. It previously booted a rendered
developer review twice. Production now builds field/prefab data before rendering,
captures actual loading photographs, bakes the map and opens the published save.
The old developer qualification remains available separately. Source creation,
fresh full-game reopen with all four map cache hits, cancellation, native damaged
section rejection, and explicit-PCK generation/reopen pass. Selector, creation,
generation and restored map images were inspected. See
[evidence/unified_generation_flow](evidence/unified_generation_flow/README.md).

The generation-only native lake job now replaces frame-paced lake authoring. It
preserves the accepted volume/contact algorithm and exact saved bytes. Native
authoring measured about 0.9–2.2 seconds, versus the earlier 15–29-second paced
stage. In-flight cancellation, time budgets, protected existing saves and actual
source/PCK creation/reopen pass. It also exposed two map bookkeeping defects:
exact block paging advanced an unsaved content stamp, and water serialization
advanced a logical map revision. Both now preserve unchanged content; cursors
still invalidate on residency changes and authoring still invalidates maps.
The saved-water alias also uses the exact snapshot identity and raster size.
See [offline_generation_bake](evidence/offline_generation_bake/README.md).

This closes that duplicated review workflow and generation-authoring handoff, not
the complete rewrite. Latest source runs observed 29–42 seconds; the explicit-PCK
connected run took 60 seconds, including 36 seconds for photo residency. These are
different warmed/cold seeds/layouts, not controlled speedup ratios or universal
instant generation. First rendered photographs, scene finalization/handoff and
whole startup cost remain required generator/loading work. Do not reopen water
flow or art direction. The later selective-residency section above supersedes the
full-expansion/history-cap limitation; prefetch and rendered pressure remain open.
Full options/POI coverage, compute equivalence and
benefit, world visual quality, populated runtime/thermal proof, and clean-machine
release installation also remain open. Unused Blender source import was disabled;
the updated resource pack starts and reopens with 14 external native DLLs.

## Native dirty-page saves integrated - 2026-10-23

Compound saves now freeze changed native terrain pages and merge touched regions
against their bound checkpoint. Full-history sample copying and recompression are
removed from subsequent unchanged/local saves. The 2,048-excavation production
fixture captured zero unchanged sample bytes and 12 KiB for one local edit, with
exact reopen, backup, root-failure retry and asynchronous edit/save ordering checks.
See [evidence](evidence/terrain_dirty_capture/README.md). This is not completion of
terrain storage: key scans, legacy block copies, compressed-history verification,
prefetch/admission, retention-aware cleanup and the rendered mining arrival gate
remain open. Selective residency and native beyond-cap capacity now have the
separate evidence above; populated rendered pressure still needs qualification.

## Terrain edit rejection is transactional - 2026-10-23

An allocator probe confirmed partial brush edits after a returned failure.
Staged native edits, allocation rollback, safe map allocation and preallocated edit
replies now pass 512 fault combinations / 224 forced failures with zero tracked
allocation leaks. Successful fields, receipts and three generated earthworks
archives retain their earlier exact hashes. See [evidence](evidence/terrain_edit_atomicity/README.md).
This establishes a prerequisite for incremental captures; it does not close full
capture/recompression, paging, cleanup or the failed rendered mining-arrival gate.
Continue the native dirty-page/checkpoint work in TERRAIN_REGIONAL_STORAGE.md.

## Character integration checkpoint — 2026-10-23

Original Human R11 and Zombie Lab packages are preserved in asset-only baseline
`e63a36d8`. Character work uses an isolated `codex/character-integration` checkout.
The 2026-10-23 pause synchronization combines the latest world checkpoint
`3e568575` with character/navigation checkpoint `f9e4b4ad`, preserving both histories.
The original world branch can advance to this combined checkpoint without a
rebase. Shared structures DLLs were rebuilt from the combined sources in both
variants; source merges had no conflicts. Integration checks and their exact
binary identities are retained in [sync evidence](evidence/character_world_sync/README.md).
R11 replaces first-person box hands/pickaxe/axe, and bounded R4 zombie encounters
now use loaded collision and existing melee/tool-wear adapters. See
[contract and remaining requirements](../addons/characters/README.md) and
[evidence](evidence/character_integration/README.md). Scoped runtime/world checks
pass; the old combat and packaging suites still fail identically on the baseline.
Those failures remain open and are not overridden by the new fixture passes.

User playtesting then exposed cancelled autonomous windups and overlapping zombie
movement capsules. The initial contact fixture had omitted per-tick manager
refreshes. Idempotent behavior changes, solid peer/player collision, bounded local
steering and reachable prone/standing clearances now have new crowd and live-host
checks. See [failure reproduction and fix evidence](evidence/zombie_encounters/README.md).
This corrects the earlier autonomous-attack claim; that earlier fixture alone did
not establish working encounters in the actual host loop.

The navigation follow-up connects zombies to the existing native `ActorRoute`
core through an external-body service, retaining one character body/motor owner.
The shared [navigation standard](NAVIGATION_STANDARD.md) now declares profiles,
collision layers, readiness, blocked/unavailable states, budgets and interaction
permissions. Local wall/stair traversal, moving goals, water avoidance, geometry
invalidation and closed wooden-door attacks have dedicated checks; retained
failures and final evidence are recorded in [navigation evidence](evidence/zombie_navigation/README.md).
Door attacks use authored contact timing and existing world durability/removal,
with no player salvage or tool wear. This updates the earlier obstacle-navigation
requirement only for the checked local cases.

Regional walking navigation now has a derived height-aware graph and bounded
collision interests. Checkpoint `adf6c72f` records the implementation; world
checkpoint `6e3575fc` is merged as `8ae421d8`, with combined native libraries rebuilt.
The later native-lake/map-identity checkpoint is included by the synchronization
above. Selected actual saved-world tower and cave journeys pass in both directions. The tower
pursuer breaks the intact wooden door and reaches the second upper floor; the
cave pursuer reaches the player beneath its terrain roof and returns outside.
All210 tower and37 cave source files, including regional sidecars, remain unchanged.
Debug/regional/release fixtures and inspected images are retained in
[evidence](evidence/regional_navigation/README.md); earlier failures remain visible.
The detailed bounds and policy are in [REGIONAL_NAVIGATION.md](REGIONAL_NAVIGATION.md).

This closes the earlier wholly-unimplemented regional graph, tile/floor walking
connections and selected cave-journey requirements. It does not close arbitrary
world reachability: the host admits at most six residents within96m, and distant
80m residency evidence is component-level. Required continuation: faster cold
planning (selected outbound queries still9.8-21.8s across rendered/headless checks), actual full-domain pressure and
travel, current owned-mine and broader seed/building journeys, continuous moving
targets and heterogeneous crowds. Resume these now that the shared graph exists;
close them with autonomous live-host travel, explicit unavailable/recovery and
measured workloads. Automatic authorized ladder/jump links and tighter crawler
clearance need their own capability/interaction checks. Door destruction still
needs fresh-process compound save/reopen beyond its provider snapshot round trip.
A rendered773ms interval and cooperative planning overruns remain recorded; total
CPU/frame, large populations, foot planting and world/art acceptance remain open.
Do not expand population or claim whole-world navigation from the selected passes.
Further world integration must merge sources and rebuild libraries together.

This is a first integration milestone, not completed survival gameplay. Required
continuation: player health/death/respawn, saved encounter identity/state and loot,
broader traversal/link coverage, third-person/outfit presentation,
authored empty-hand punches and construction grips, draw/stow transitions and
camera/tool wall clipping, plus sustained population/frame-cost qualification.
These are deferred because this milestone preserves native movement and existing
world save schemas while admitting the source rigs. Resume after the rig/spawn
contract is accepted; close each with actual gameplay, save/reopen or rendered
animation evidence as appropriate. The original source reports do not certify
this host integration or close the wider world visual/performance gates.

The relaxed placement follow-up supplies one Blender-authored empty-hand gesture:
the whole hand is low with a neutral wrist, a slightly extended index and natural
thumb. Empty hands keep the original idle between actions, including while moving;
the one-shot automatically lowers the hand back to rest. It is presentation for accepted single-block/terrain-fill submissions,
not a construction-tool grip or general interaction system. Editable source,
runtime animation, review images and targeted host checks are linked in
[placement evidence](evidence/human_placement/README.md). The other presentation
requirements above remain open.

The zombie dragging-walk follow-up adds an in-place Blender-authored right-leg
drag with a weight-bearing left step and a continuous two-second loop. Standing
pursuit defaults to 0.45 m/s with matched playback; original R4 actions and
severed-leg crawling remain available. Flat-floor evaluated-skin checks and real
controller transitions for that original draft are in
[gait evidence](evidence/zombie_drag_walk/README.md). The user rejected its stiff,
floaty presentation on 2026-10-24. The current **revision 2** rebuilds
support/recovery timing, heel/toe roll, weak-side collapse,
spinal follow-through and uneven hanging arms. Playback now follows measured
body travel, including holding the gait when collision stops the body. Its 24
gait checks, 17 encounter checks, nine rendered actual-world combat checks and
two slope cases pass. Normal/half-speed review media, sampled sole-contact
measurements and initial failed runs are in
[revision 2 evidence](evidence/zombie_weighted_limp/README.md). Visual acceptance
remains open for user review of that preview; passing checks do not establish
realistic presentation on uneven terrain.
The previous selected tower/door/upper-floor round trip also passes at this slower speed
with all 210 source files unchanged. Cold paths in that uncontrolled run take
20.3/40.2s and cooperative planning overruns remain; the animation does not close
the existing navigation timing requirement.
This is animation presentation and a deliberate speed change, not new traversal
capabilities. Terrain foot planting, larger populations and the broader regional
navigation/performance requirements remain open.

The diagonal pickaxe follow-up is an **uncommitted review draft in the character
worktree**. It adds a diagonal ready grip with the left hand below the right and
a forward strike from the right with a small left/down diagonal, plus matching
tool locomotion holds. The initial sideways sweep was rejected; the first forward
revision was too centered. The current revision keeps hands/handle on the right
and only 6–8 degrees of left shaft roll through contact and a short follow-through.
The 20–24 degree revision was rejected for excessive left twist; torso turn is
also reduced to one degree. The working point stays right of center. Engineering
and rendered review evidence are in [pickaxe draft evidence](evidence/pickaxe_diagonal/README.md).
Visual acceptance remains open: the user explicitly requires approval before
any commit. Return when the user has reviewed the video and approved the grip,
hand deformation, camera crop and swing timing; otherwise revise the draft.
Do not merge it into the ongoing terrain branch before that approval.

The user asked to keep the reduced-twist v4 candidate and try a separate full
right-to-left sweep. That experimental copy was rejected as a complete visual
regression on 2026-10-23. It never replaced the game's v4 selection. Its source,
tools and review stills are archived in
[rejected full-sweep evidence](evidence/pickaxe_full_sweep/README.md), outside the
character addon. All eleven preserved v4 source/runtime/tool/test/video hashes
still match. The requested broader swing without leftward twist remains
unresolved; the rejected copy is not an accepted implementation. Any future
attempt must start from the kept v4 candidate and receive visual review before
replacement or commit. No further variation is being authored during this
rollback; animation approval and terrain synchronization remain pending.

A second copy preserved v4 through contact and added a left follow-through.
The user also rejected that result; its passing engineering checks do not qualify
the appearance. Source and review evidence are archived in
[rejected left-follow evidence](evidence/pickaxe_left_follow/README.md).
The current request is a fresh copy of preserved v4 with a strike from the right
side rather than from above. Both rejected continuations are excluded as motion
sources. Visual approval, committing and terrain synchronization remain pending.

The separate side-strike draft is now authored from the exact preserved v4 blend.
It retains the ready grip, draws back lower to the right, drives forward
diagonally, keeps the shaft leaning right and torso neutral, and recovers from a
short follow-through. It is available only in the review preview; v4 remains the
normal gameplay selection. Twelve scoped runtime/animation checks pass, and an
eight-second studio video plus stills are retained in
[side-strike review evidence](evidence/pickaxe_side_strike/README.md).
The widest wind-up partially crops at the right/bottom screen edges. The user
reviewed this as a good alternate and requested a separate copy with more
pullback toward the player before launch. The liked side-strike assets remain
unchanged and uncommitted. The newer
[deeper-pullback copy](evidence/pickaxe_side_pullback/README.md) adds 8 cm toward
the player during wind-up and rejoins the liked action at frame 28; contact,
follow-through, recovery and ready poses are preserved. Nine scoped comparison
checks pass. The user reviewed that deeper pullback as better and requested a
test copy with a small rightward tool twist and a swinging motion throughout,
replacing the straight pushing quality. The liked deeper-pullback assets remain
unchanged. The new [arc-swing test copy](evidence/pickaxe_arc_swing/README.md)
adds a five-degree rightward tilt during the stroke, uses an elliptical lower-hand
path with more tool rotation, and curves the wind-up and recovery. Forward contact
is preserved; lower-hand forward extension falls from about 22 cm to 10 cm.
Twelve scoped animation checks pass. Its normal/half-speed studio video awaits
user visual review, including the widened right-edge wind-up crop and recovery.
The user then explicitly authorized committing and syncing the work. The liked
deeper-pullback side strike is now selected for gameplay, with diagonal holds;
the latest arc-swing copy remains an unselected visual test. Earlier no-commit
statements are historical. Character runtime, packaging, pullback/arc comparison
and diagonal-world checks pass. The actual-world placement test verifies the new
default action and idle return. The terrain-fill-feedback failure was traced to
the test retaining gameplay's excavation-only admission policy after switching
building inventory to editor costs: its sample was queued, not accepted by the
terrain worker. The fixture now checks rejection without mutation/animation,
then explicitly selects editor admission for cube and brush fills. Actual native
publication, gesture activation and idle return pass in headless and rendered
42-check world runs. This closes that specific reported failure without changing
gameplay edit permissions. See [fill-feedback correction](evidence/terrain_fill_feedback/README.md)
and the earlier [integration evidence](evidence/pickaxe_integration/README.md).

## Regional terrain checkpoint integration - 2026-10-23

The character worktree was fast-forwarded to the latest committed terrain
checkpoint `17f949a9` on 2026-10-23. All animation drafts remain uncommitted and
unchanged; only this shared status document required a clean three-way merge.
Character runtime, the arc-swing copy, zombie dragging walk, temporary-world
pickaxe playback and rendered loading-UI checks pass on the combined state.
See [synchronization evidence](evidence/animation_terrain_sync/README.md), including
the retained incomplete headless UI attempt and successful rendered rerun.
This synchronization does not resolve animation visual acceptance or authorize
committing the animation work. Later terrain commits still require another sync.

Actual compound saves now select native compressed, immutable terrain packs;
source generation, fresh reopen, exact prior-world equivalence, corruption/failure
protection, cloning and recovery have scoped checks. See
[TERRAIN_REGIONAL_STORAGE.md](TERRAIN_REGIONAL_STORAGE.md) for formats, evidence
and required continuation. This is not yet native selective residency: full
capture/recompression and full expansion still occur, and the resident cap is
unchanged. Dirty-page capture, paging and retention-aware cleanup/compaction remain
immediate requirements before storage/long-run readiness can be accepted.
Explicit --main-pack child propagation now passes actual bundled creation/reopen
and publication (d4340f6f90ce21f9e3b5a0f5abc1542c), with identical complete-world
signature. Earlier failed launcher checks are retained; startup alone was insufficient.

## Terrain history storage evidence - 2026-10-23

The broader persistence rerun still fails pending lake shutdown capture and
deleted lake ID retention (20261023T075205102867Z). These are reproduced current
defects, not historical assumptions. Investigate provider drain/cursor persistence
before comprehensive persistence acceptance; ordinary save/reopen passes.

Native edit arithmetic remained bounded through 2,048 distributed excavations;
archive capture grew with history. One output reservation plus format 3 CRC32C
reduced capture cost in the scoped check, with exact restore and legacy backup
migration verified. See [evidence](evidence/terrain_history_storage/README.md).
This does not close the monolithic terrain store, resident page capacity,
selective loading, combined save latency or the failed rendered arrival gate.
These remain active next requirements, with capacity/travel/recovery/save-reopen
and visible-latency evidence required before closure.

## Rewrite checkpoint — 2026-10-23 (work remains active)

Native road/lot planning, shared preview/bake plans, layout options, engine-owned
creation and verification, generated lake initialization, loading photographs,
root-last publication and interrupted-publication recovery are implemented and
have scoped evidence in WORLD_WORKFLOW_REDESIGN.md. Source and bundled generation
have passed; the latest exported pack starts, but clean-machine release installation
and current full bundled integration still require verification.

Vegetation now scatters detail without repeated four-metre rows. Stable harvest
identities and base stones remain; procedural detail positions change. Normal-view
circular prefetch passes a66m walking check with zero missing visible owner-frames,
no rejected publications and no deferred renderer pages. The repeat endpoint was
inspected. Distant terrain canopy shadows use a bounded native worker mask, while
nearby real shadows remain. These do not prove zoom/high-speed/teleport continuity
or sustained populated-world cost. See evidence/vegetation_rewrite/.

Still required in this same rewrite: complete options and map layers; bounded
native parallel generation/compute integration with equivalence and benefit evidence;
canonical regional storage capacity/recovery; large-edit/mining scaling; remaining
vegetation streaming cases; clean standalone export; populated travel/frame-cost
checks and world visual acceptance. These remain active, not optional. Preserve
0BSD, existing saves and accepted static water. Held mining after scripted arrival still fails the150ms first-visible-change
gate after correcting its obsolete tool setup. Native fallback now applies to the
ordinary renderer, but readiness/large-edit scaling remain open; see the exact
failure reports in WORLD_WORKFLOW_REDESIGN.md.

## Native world-generation rewrite in progress — 2026-10-22

Regional road search/surveys, street grading, building lot searches and entrance
fit now use production C++ APIs. The generator UI and actual bake share a cached
placement plan. Full creation and fresh-process restoration pass for
`native_world_rewrite_42_20261022`; cached loading photos were inspected.
[Evidence, measured timings and remaining requirements](evidence/native_world_generation/README.md).

This closes the scripted road/lot computation and disconnected placement-preview
steps, not the entire rewrite. Native job orchestration/compute, standalone
creation, complete map layers/settings, canonical storage/capacity qualification
and sustained performance remain active requirements of WORLD_WORKFLOW_REDESIGN.
Visual settlement quality remains unaccepted; this implementation preserves the
current recipes. No water or gameplay-detail milestone replaces this priority.

## Active priority changed — 2026-10-22

The user stopped mine/POI detail work. The active deliverable is the unified world
generator, selector, loading presentation, map, native/compute generation pipeline,
baking, caching and storage described in [WORLD_WORKFLOW_REDESIGN.md](WORLD_WORKFLOW_REDESIGN.md).
Earlier next-step instructions for mine integration are superseded. Open defects
remain tracked; UI improvements do not close native generation or capacity work.

## Current unfinished-work handoff — 2026-10-22

This is the current priority index, not an exhaustive replacement for the open
requirements and evidence in the chronological entries below. Moving to another
milestone does not close those requirements. Each deferred item must retain a
reason, prerequisite/return trigger and closure evidence.

| Work | Status and reason | Prerequisite / return trigger | Required closure evidence |
| --- | --- | --- | --- |
| Generated market cellar storage | Scoped interaction/persistence checks complete; see `evidence/market_cellar_storage/` and `evidence/market_cellar_persistence/` | Recheck if storage, prefab placement or loading changes | Actual route, exact inventory roundtrip, gameplay-mode deposit/save/fresh-process reopen and reached chest identity/protection all pass; this does not close room art or broader persistence failures |
| Cellar room presentation | Unreviewed; prior room capture was obstructed by the ladder | After storage interaction, before calling the location accepted | Clear interior capture and review of usable circulation and furnishings; human acceptance remains distinct |
| Connected regional destinations and owned mine | Incomplete; current default world has only two public places | Main world-generation milestone after the cellar check | Actually generated accessible locations, connected roads, intentional underground access, map agreement and fresh-process reopen |
| Regional landscaping and travel quality | Incomplete; exposed banks and route quality cannot be accepted from planning checks alone | Alongside regional content integration | Inspect road/terrain transitions and junctions; complete ground/vehicle travel on the actual generated routes |
| Edited-ocean streaming | Deferred so world-content work can proceed; resident capacity failure remains open | Before large-world readiness qualification, or immediately if ordinary play reaches capacity or threatens saved edits | Complete runtime ownership/selective loading, retained far/map edits, quantity accounting and retention; pass edited travel/capacity and save/reopen checks. See [storage contract](OCEAN_EDITED_STORAGE.md) |
| Integrated world performance | Not qualified by isolated passes or a 60 FPS screenshot | Once representative connected content is available, and whenever an ordinary-play regression appears | Short diagnostic checks first, then representative 1920x1080/60 FPS travel and sustained measurements with recorded hardware/settings and CPU/GPU/memory evidence |
| Legacy world persistence regression | Last recorded broader check failed lake shutdown-drain and ID reuse assertions; later narrow water checks do not establish closure | Before comprehensive persistence acceptance; sooner if the ordinary save path shows a related failure | Reproduce or disprove the exact failing assertions on the current build, retain logs, and verify combined save/reopen without weakening the assertions |
| Model paging and arrival | Historical checks do not qualify detailed populated-world residency or all arrivals | Before promoting paging/defaults or claiming large populated-world support | Inspect current runtime defaults, then test the same populated route with edits/save/reopen, visible/collision readiness and bounded residency |
| Save/reload latency and storage growth | Historical measured hitches and capacity/recovery gates need explicit current-build closure | During integrated loading/storage qualification; immediately for an ordinary-play regression | Measure actual dispatch/restoration, verify failure recovery and authoritative/cache bounds, and attach evidence for each previously failing stage |
| Map cost and edited-world coverage | Regional coverage has progressed beyond the older register; cold work and full edited-world qualification remain open | Alongside additional destinations and edited-world travel | Verify current terrain/water/block/model layers against the saved world, with cache invalidation, reopening, useful zoom and bounded work; do not reimplement already completed layers |
| Vegetation continuity | Near gameplay exists; distant/bulk-change continuity and combined budgets are unqualified | Inspect along the connected regional routes | Ground/elevated travel and harvesting checks with the accepted sparse distribution, no area flicker or unsupported vegetation, and recorded resource costs |
| Entities and authority boundaries | Stores and limited residents are not representative simulation or multiplayer proof | Before expanding population-dependent world content | Representative activation/navigation/animation workload and ownership/command audit; networking implementation remains deferred by user direction |
| Standalone delivery | Local tooling and launchers do not prove a clean installation | After coherent world integration, before distributable/release acceptance | Create/open/export on a clean installation without the development Python/toolchain; verify supported configuration and recovery |

Water remains static: flow and spillage are deliberately excluded, not pending
requirements. Preserve existing saves. Review earlier open entries when their
prerequisites become available, and explicitly record closure evidence rather than
assuming a later successful test covers them.

The older "Playable world foundation - current contract" coverage register below
remains the broader scope checklist. Its dated implementation descriptions are
historical: reconcile them against later evidence and current code before scheduling
work. In particular, later ocean-map evidence establishes regional map coverage;
the older row saying the live water layer is absent is not a current implementation
claim. A new narrow pass cannot silently close a broader historical failure.

## First baked regional connection — 2026-10-20

The terrain-fitting seed42 neighborhood now has an approximately 413 m forest
road toward the central site, baked as ordinary native terrain edits and persisted
with the neighborhood. Play Terrain-Fitting Neighborhood.cmd defaults to a separate
v3 editable copy of terrain_connected_clear_20261020. --review-version 1 or2 keeps
previous sources/copies accessible. Existing saves were not overwritten.

The bounded offline planner surveys a16m grid within a256m corridor margin, uses
native AStar3D over grade-limited adjacent nodes, excludes lake/POI/other-site areas,
and verifies actual candidate corridors at2m stations including lateral support.
Invalid edges are removed and search retries at most32 times; no relaxed grade or
cut/fill fallback. Shortcut removal also requires full corridor survey and native
128m segment limits. Terrain and native path search own heavy queries; GDScript
coordinates offline planning. No route search runs during normal play. Seed42
uses2,474 graph nodes and six route points. Other seeds/routes are not yet qualified.

Native application verifies1,290 road surface probes with zero mismatches. The
35.49-second integrated creation check prepares the arterial before local streets,
places all12 buildings, walks the existing sidewalk and durably saves. The14.92-
second fresh-process check restores two public destinations and277 map segments.
The central marker explicitly says construction is unfinished; no nonexistent town
is advertised. Evidence: evidence/terrain_regional_connection.

Initial rendering exposed trees on new roads. Saved native region metadata now
builds a64m spatial index for vegetation clearance queries; tree and procedural
ground-cover publication filter against it, including subsequent stream-in/reload.
It uses a2m tree-root margin and0.3m ground-cover margin beyond road width, with
vertical separation to avoid suppressing unrelated levels. Native tests cover mask,
invalid margin and index rebuild on snapshot restore. Reopened runtime found zero
road-root overlaps among3,370 rendered trees. Hand-authored ground-cover objects
are not automatically removed. Root exclusion is not canopy or all-prop clearance.

Inspected ground/overview images show the forest road exists and is clear at the
reviewed position. Exposed scalloped banks still need landscape treatment. This is
not full visual acceptance: junction, complete vehicle traversal, turning comfort,
central-site construction and remaining roads/lakes/POIs remain mandatory next work.
Screenshots at60FPS do not establish sustained performance or thermal headroom.
The earlier legacy lake-persistence failures remain recorded and unresolved.

## Regional exclusion planning — 2026-10-20

Terrain-lot selection now reserves native lake catalog bounds plus 12 m shore
margins, the mine underground footprint plus 12 m, its entrance approach, and the
other four settlement planning footprints plus their transition margins. Descriptors
come from the same native world being surveyed. Missing metadata rejects planning;
these reservations do not publish nonexistent destinations or alter water behavior.
A conservative candidate envelope rejects overlaps before street solving; the final
actual earthworks AABB is checked again before acceptance. Existing generated saves
are unchanged. All seven seeds retain 12 lots. Six retain their prior offsets, including the
reviewed seed42; seed0 is relocated to avoid a reserved footprint.

The profile17 regression checks final earthworks against all ten reserved areas
and tests that probes inside each reservation are rejected. Native seed42 earthworks
still pass support, road, pavement and exact terrain persistence checks. Evidence:
evidence/terrain_region_reservations. This step adds no new visible world content;
the prior reviewed images still describe the unchanged chosen neighborhood.

These are reservations for existing native hints, not a finished regional planner.
When multiple settlements move, their actual occupied footprints must be reserved
transactionally, replacing the planning hints, before regional roads and POIs bake.
Route crossings/bridges and owned mine access need explicit planning. Continue full-
region integration; do not equate exclusions alone with a complete connected world.

## Lower-disturbance settlement siting — 2026-10-20

The offline planner now ranks feasible street locations before fitting buildings,
rather than returning the first passing location. Search stays bounded to625
candidates within288m of the original district hint, clipped to world bounds. The
score uses mean absolute road cut/fill, maximum cut/fill and a small displacement
penalty. All12 buildings, 2m fill/3m cut limits, frontage checks, pedestrian
clearances and existing native road grades remain mandatory. No runtime search.

For seed42, selected road mean cut/fill falls0.747m ->0.496m, maximum fill1.334m
->0.754m and maximum cut2.146m ->1.889m. The district moves168m east/288m south
of its original hint. Seven seeds pass; the regression explicitly compares42
against its previous passing site. Native application still uses210 edits and
checks2,608 foundation points plus road/pavement probes with no mismatches.
Terrain snapshot roundtrip is exact (1,733,208 bytes). Other seeds are checked for
validity, not claimed to improve over their previous locations without comparison.

The real-world33.33-second creation/walk/save check and7.27-second fresh-process
reopen passed without diagnostics. Inspected street/overview images show gentler
banks and reduced exposed cuts at the reviewed street. This is scoped visual
improvement, not acceptance of every roadside or the complete world. The launcher
now opens a distinct v2 copy of terrain_ranked_neighborhood_20261020. Its
--previous-review option retains the prior source/copy; no existing save was moved.
Evidence: evidence/terrain_ranked_neighborhood.

A tested retaining-wall approach was rejected after image inspection: large
concrete segments made the neighborhood look heavier. That implementation was
removed and never published as a review save. Its local trial images remain in
reports/retaining_wall_rejected. Prefer suitable terrain before adding structures
whose only purpose is hiding an unnecessarily poor site.

Next required integration: connect this terrain-fitting layout to the full region,
account for lake/mine/other-site exclusion footprints, generate the other settlements
and owned POIs, and finish public-space/entrance/vehicle review. Current generator17
still has only one developed neighborhood and no baked regional water/roads. Building
variety and middle-distance vegetation continuity remain visibly incomplete.

## Saved terrain-fitting neighborhood — 2026-10-20

A loadable development save now exists: terrain_fitted_neighborhood_20261020.
Play Terrain-Fitting Neighborhood.cmd opens a separate editable copy at the new
neighborhood; the prior full-region review and existing saves remain unchanged.
This is ONE developed neighborhood in profile17, not a completed replacement region.
Regional connections, other settlements, authored lake filling, landscaping/public
spaces, road-cut treatment, facade variety and broad traversal remain required.

NativeGeneratedRegion stores the actual baked public locations and sampled road
lines. Map/destinations use these persisted coordinates for17; they no longer infer
built streets or lakes from planning descriptors. Publication follows successful
terrain/building/paving completion. Old saves use an empty default component and
retain their existing legacy directory. The native format is bounded and validates
coordinates, labels, identity, duplicate IDs, truncation and exact payload length.

Integration exposed the existing63-provider archive ceiling. The bounded ceiling
is now127 providers plus terrain (128 sections), with unchanged total byte limits.
Old archives remain readable; new >64-section saves require this updated runtime.
Tests cover exact128-section roundtrip and129-section rejection, invalid metadata
transactionality, and full-world save/fresh-process restoration. The integrated
34.64-second check completed12 buildings and210 edits, walked the player on a
sloping sidewalk, and durably saved. Fresh-process reopen took9.13 seconds, with
one baked destination and272 road segments restored exactly. Both were diagnostic-
free. Street screenshot shows54 FPS: sustained60/headroom is NOT established.

Evidence: evidence/terrain_fitted_saved. Images inspected: sidewalks follow grade,
but exposed raw cuts and repeated facades still prevent world-quality acceptance.
A broader legacy world_persistence check also failed lake shutdown-drain and ID
reuse assertions (retained log). Its failure is unresolved; do not claim the whole
persistence suite passed. It is outside this no-water-work milestone and must be
triaged before comprehensive persistence acceptance. No water behavior was changed.

## Terrain-supported pedestrian paving — 2026-10-20

The new terrain-fitting neighborhood now reserves pedestrian corridors before
placing buildings. Residential carriageways are 6m wide, with1.5m walkways on each
side and an additional surveyed1m terrain support margin. Native soil beds precede
asphalt so the final surface keeps its road material. Paving uses one registered
shared concrete box mesh, existing concrete texture and NativeStaticBatch storage/
rendering. Terrain supplies collision; there are no added per-slab collision bodies
or runtime GDScript placement loop. The visual layer sits15mm above its support.

Planning considers49 local positions per plot and169 bounded district candidates,
with four permutations of the same12 building assets. It never silently drops an
unfitting building or increases cut/fill allowances. All seven seeds locate12 plots
and entrances with pedestrian clearance. Seed42 now moves120m south. Planning-only
checks take about10 seconds; they are offline and not runtime performance evidence.

The native seed42 check applies210 sections, verifies2,608 building support points,
checks road interiors and pavement surface probes, and roundtrips terrain bytes.
Pavement originally intersected terrain at the grading edge; the corrected road/
walkway widths and support margin remove those mismatches. The31.54-second real-world
visual check passes without diagnostics, restores exact paving model snapshots, and
walks the actual player about5m along a sloping pavement without jumping/flying.
This short walk is not coverage of every sidewalk/crossing/entrance.

Inspected street/overview evidence: docs/evidence/terrain_lot_paving. Paving follows
the street grade, but road cuts remain visually exposed, the repeated building layout
is not accepted, junction-crossing continuity needs more walking, and vegetation
residency/coverage varies between captures and remains unqualified. This is still a
temporary neighborhood check, not the new full-region review save. Public areas,
parking, regional road connections, baked map/destination metadata, exclusions and
fresh-process full-world restore remain mandatory before promotion. Continue these
integration tasks; do not call the world foundation complete.

## Native earthworks and rendered neighborhood — 2026-10-20

Generator17 is an immutable ungraded regional landscape: the natural mountain/lake
field remains, but automatic regional road/settlement grading and asphalt are absent.
It is for baking terrain-fitting development as ordinary saved edits. IDs1–16 are
unchanged. It is NOT selected by the public review launcher or preparation default.
Its legacy site/road descriptors are planning hints, not built roads or accepted
settlement locations; map/destination integration must use the eventual baked plan.

Terrain-lot earthworks now run through the normal asynchronous site-preparation
path. Curved sections preserve selected material/shoulder values. Seed42 prepares
136 sections and places all 12 furnished buildings in the real world scene. Native
checks cover 2,608 foundation support samples, road surfaces within +/-0.5m of their
planned height, and an exact native terrain snapshot roundtrip. The street test
initially found ten bad samples from overlapping sloped end caps. Continuous cubic
profiles, shared level junction footprints and painting roads after entrances fix
those failures. Cubic sections reserve their 1.5x peak derivative within 12% grade.
All seven seed planning checks still pass; native edited-surface checks cover seed42.
Existing no-op preparation and graded-bed persistence checks also pass.

The clean 1920x1080 world capture took26.33 seconds, with no engine diagnostics.
Inspected overview/street images in docs/evidence/terrain_lot_native show actual
buildings and sloped streets on preserved natural ground. The first capture caught
a duplicate resource registration in the test harness; registration was corrected
and the check rerun cleanly. The final images are NOT final-quality acceptance:
road cuts remain exposed, layouts repeat, sidewalks/common areas/parking are absent,
and surrounding vegetation/far-field transitions still need review. Captured60FPS
is not sustained-performance evidence. No human review save was replaced.

Required next: integrate this plan into full region preparation with regional road
connections, mapped baked geometry/destinations, water/mine/site exclusions,
terrain-fitted sidewalks/common areas/parking and saved attachments; assess shoulders
and all edited footprint displacement; walk and drive entrances/junctions; verify
full-world fresh-process restore, then promote a new review copy. The current raw
profile is not a drop-in replacement for existing level district recipes.

## Terrain-fitted planning implementation — 2026-10-20

Added offline terrain_lot_planner.gd, not yet wired into world preparation. It
surveys all occupied foundation cells against native undeveloped terrain, searches
25 placements per frontage, chooses integer grades within 2 m fill / 3 m cut,
reserves building/street clearance, and rejects missing plots explicitly. Streets
have shared elevation vertices and a bounded interval propagation solve for 12%
grade. Width and interior probes reject cut/fill violations. Entrance paths connect
each building to its actual street grade, with 25% maximum slope and raw-terrain
cut/fill checks. A bounded 81-location search relocates the whole neighborhood when
its original site cannot fit; it never increases the terrain-change allowances.

Seven seeds now find all 12 plots with street/entrance plans, in 2–24 candidate
locations. Seed42 requires a 96 m southward relocation. The independent check uses
additional street sampling locations and rechecks all final foundation elevations.
The complete check takes under five seconds headless. Evidence is in
 docs/evidence/terrain_lot_planner. This is engineering evidence of prospective
plans, not visual, collision, earthworks-edit or integrated world acceptance.

Still required before replacing the current world: versioned native unflattened
settlement field; regenerate regional road endpoint/grade at the chosen site;
lake/mine/existing-site clearance; terrain-fitting sidewalks, common furniture and
parking; complete foundation and shoulder edit bounds; avoid entrance-road overlap
with neighboring buildings; apply/validate plans with native terrain edits; save/reopen,
render and walk the real generated location. Do not publish this helper as a finished
world or switch the launcher until those dependencies have been integrated.
Keep current generator IDs and player saves unchanged. Continue settlement work.

## Raw terrain earthworks rejection — 2026-10-20

The previous lot checks sampled already-flattened generator terrain. They verify
local authoring correctness, NOT the world-building cut/fill standard. Native
command 37 now reports paired undeveloped/developed heights in bounded batches of
256, without changing world state. Undeveloped retains natural mountains and basins
but omits regional settlement/road grading. Runtime height calls default to their
existing behavior; generator IDs and saves are unchanged.

A 4 m grid inside all five site radii across seven seeds rejects all 35 generated
pads against 2 m fill / 3 m cut limits. Seed 42 north: 10.413 m fill, 2.719 m cut;
central: 12.417 m fill, 10.956 m cut. Sampling is a lower bound on worst displacement,
not an exhaustive surface proof. This is enough to reject these layouts. Source
surveys in docs/evidence/regional_earthworks/survey.json preserve every result.
The --enforce-quality check intentionally exits 1 (35 violations, zero protocol
failures). Do not interpret the default audit's exit 0 as world-quality acceptance.
Existing generator-15 corridor checks still pass after the read-only height API change.

Required next implementation: a new immutable generator profile that retains raw
land between individual building/street footprints; site planning must choose
per-lot grades against raw terrain, route streets between those grades, and relocate
or omit unsuitable lots before any edits. Existing level sidewalk/common-area/
parking recipes must follow the same grades. Do not simply disable broad pads while
leaving those dependent plans level, enlarge plateaus, or relax the earthwork limits.
Then regenerate and inspect integrated ground/overview views and walk entrances.
Current v18 remains a development review; no visual fix is claimed for this audit.

## Surveyed regional locations — 2026-10-20

Generator 16 surveys 45 candidate locations for each outer settlement against raw
terrain relief and lake clearance. Roads retain cardinal approaches into authored
streets while following terrain-cost corridors through the countryside. Existing
generator IDs and saves remain unchanged. This does not enforce a complete cut/fill
budget: generated settlement plateaus and regular internal layouts remain rejected
for final world quality.

Seven-seed route and lot checks pass. All 28 roads bend; maximum grade is 0.120001,
and maximum centerline surface error is 0.091 m. Full seed-42 generation and fresh
process restoration passed (reports/combined_preparation/20261020T171213014996Z).
The 26.85-second integrated visual capture passed without engine diagnostics.
Inspected ground and neighborhood views show forested road travel and the shifted
northern settlement, but also repeated buildings and overly smooth surroundings.
The ground capture reads 46 FPS: these images do not establish sustained 60 FPS.
All-route vehicle traversal, shoulder earthworks, streaming cutoffs and thermal
headroom remain unqualified.

Play Regional World Review.cmd now opens a separate editable v18 copy of
sited_region_42_20261020, generator 16. Preparation uses --layout districts --natural
--seed 42. Next content priority: settlement layout/terrain integration and purposeful
location variety, not another cache or reload optimization pass.

## Generated terrain-cost road corridors — 2026-10-20

Generator15 replaces straight regional road centerlines with bounded offline corridor
searches (25 stations, nine lateral choices per station). Terrain-height and grade
costs choose routes; smoothing reduces abrupt bends, and vertical grades are limited
to12%. Existing settlement transition bands have fixed level approaches. Native
surface/material evaluation and the map share the exact route points through command36.
Height queries reject distant corridors and examine at most five local segments per
road; no runtime pathfinding or per-road scene nodes. Generator IDs1–14 remain intact.

Seven-seed native checks pass: exact route reconstruction after save/reload, fixed
junction endpoints, maximum measured grade0.120001, centerline terrain deviation
0.0711m or less.26 of28 tested roads deviate meaningfully from their straight chords.
The initial check caught settlement blending lifting sloping approaches (up to8.74m);
fixed transition bands corrected it. An exact endpoint rounding discrepancy was also
corrected before publishing. Seven-seed lot-fit checks pass.

Full seed42 district generation and fresh-process reopen passed, publishing the
separate slot `routed_region_42_20261020`. Inspected1920x1080 overview, ground and map
images show a woodland road bend and matching map line. The map capture occurred while
water/block/object overlays were still surveying; it only verifies road depiction.
A continuous on-foot walk through three northern road segments passes with actual
player movement and collision. No teleport occurs between those route waypoints.

World quality remains incomplete: overall topology is still a five-site hub with
four spokes; settlement clusters are regular, shoulders require broader visual review,
and all-route vehicle travel/turning plus sustained performance remain unqualified.
Terrain-cost selection is not an enforcement of the ordinary-site2m fill/3m cut budget
for every road shoulder. These limits must be measured/reviewed before road acceptance.
The next world-design task is the regional location/settlement arrangement; do not
mistake this bend correction for complete natural-world generation. Evidence:
`evidence/routed_region`.

## Natural-region generation 14 — 2026-10-20

A separate immutable generator profile changes mountains from four smooth bumps to
warped, ridged landforms and introduces irregular lake boundaries inside existing
water catalog limits. It retains the accepted static water implementation. Native
woodland distribution now uses a coherent multi-scale field across all quadrants
for generator14, instead of the legacy southwest-only mask. The 36 candidates per
owner, stable IDs, resident limits and existing tree assets/LOD remain. Earlier
generators retain their original terrain and tree distribution.

The first rendered review exposed submerged trees: rendered roots sit 20 cm below
ground, while the water probe reached only 8 cm above them. Tree exclusion now probes
the supported ground surface; final lake views no longer show those submerged roots.
Ground-cover shelter queries use the same new tree field.

Full district generation and fresh-process restoration passed for seed42, slot
`natural_region_42_20261020`. Seven-seed northern lot fits pass. Native woodland
checks show deterministic candidates in all four quadrants, clearings and wooded
owners, bounded to36 candidates each. Legacy scatter byte-compatibility checks pass
(576 byte checks, 72 legacy cases). Native debug/release addons built using pinned
Zig/prebuilt godot-cpp. Final graphical inspection completed at1920x1080 fullscreen.

Inspected lake, shoreline and mountain images show broader woodland coverage and
less regular landforms. This is NOT full natural-world acceptance. Lake terrain still
has a basin-like rim, roads remain four straight spokes, settlement ground/layouts
remain too regular, and distant forest cutoff is visible from elevated views. Those
are required subsequent generation/representation work. Captures use a short settling
period; they do not qualify full residency, travel stability, sustained60FPS or older
laptop thermals. Next priority: terrain-following road corridors with shared map
geometry, followed by settlement clusters fitted to those corridors. Do not return
to loading micro-optimization as the main milestone.

## Generated village shop — 2026-10-20

The northern lot-four recipe now generates a village general store instead of a
second mine workshop. Its pitched timber roof changes the skyline; customer counters,
rear shelving and two storage chests use existing native block/model collections.
The other workshop remains. This is offline recipe work, with no new runtime processor.

Full seed-42 district generation and fresh-process reopening passed and published
`foundation_village_shop_42_20261020`. Existing saves remain intact. Lot-fit tests pass
seven seeds; the new prefab preserves its entrance, central aisle, rear-store passage
and exact resource save/reload. One initial fixture incorrectly sent attached models
to the blocks-only placement API; corrected fixture separates geometry validation
from attachment persistence, while the full-world test uses compound publication.

Inspected integrated exterior/interior screenshots at 1920x1080 show the new roof,
connected neighborhood streets, counters and open rear passage. Interior remains
sparsely furnished and needs stronger shop identity; no trade system is implied.
World quality remains unaccepted: repeated tower facades, broader landscape/arrival
quality, full connected exploration and multi-seed visual review remain unfinished.
Screenshots are visual evidence, not a frame-time or thermal qualification. Evidence:
`evidence/village_shop_world`. Next work stays on generated place quality and connected
exploration, not additional reload optimization.

## Native collection retirement; optimization stopping point — 2026-10-20

Native transient vegetation collections now detach once and retire in bounded record
steps, including members of large nested groups. New rendering waits for old pages;
reused placement IDs remain independent. Native and ground-cover regressions pass.
The integrated readonly 1920x1080 reload passed: initiation 5.903 ms, 33 preparation
frames, largest preparation slice 2.530 ms, largest restoration slice 3.289 ms.
These are scoped observations, not hard timing or long-run thermal guarantees.
Evidence: `evidence/transient_collection_retirement`.

**Direction correction:** this work did not generate new world content. Stop further
reload optimization now. The next deliverable is visible improvement to the integrated
generated region, reviewed against WORLD_BUILDING_STANDARD.md: terrain-fitting varied
settlements, connected roads and purposeful explorable locations. Existing outstanding
performance, storage and endurance requirements remain open; test them alongside world
changes rather than making further micro-optimization the next content milestone.

## Reload preparation barrier for ground cover — 2026-10-20

The terrain facade now supports ordered cooperative reload-preparation jobs. The
existing reload signal starts lightweight preparation; its frame steps run while the
world is unavailable. Component restoration cannot start until preparation finishes,
and begins on a subsequent frame to avoid combining two preparation/restoration slices.
A repeated reload cannot interrupt either phase. Failed preparation blocks save
publication and world readiness; shutdown during preparation also protects the save.

Ground cover uses this path: old batches hide immediately, native species collections
are cleared incrementally, and resident interaction-cell records are retired between
budget checks. Reply callbacks ignore stale responses while reset is active. Generator
work is suspended until completion. The synchronous reset API remains for direct use
and compatibility. Saved vegetation edits, assets, density and LOD settings are unchanged.

Tests verify ordered preparation before restoration, failure termination with writes
blocked, immediate vegetation hiding, staged completion and exact vegetation regeneration.
The integrated readonly regional reload at 1920x1080 fullscreen passed with **6.171 ms**
initiation, **8 preparation frames** and **5 component-restoration frames**. Largest
preparation slice was **12.056 ms**; largest restoration slice was **3.217 ms**. Water
interaction/quantities, retirement drainage and map-cache reuse passed. Canonical save
SHA-256 unchanged. Evidence: `evidence/reload_preparation_budget`.

**Not a hard timing guarantee:** an individual native collection clear is still atomic,
so preparation can exceed the configured 1 ms cooperative budget. The 12.056 ms maximum
needs further investigation before claiming ample headroom on older hardware. The
world remains gated during these operations; no partial runtime state is exposed.
Repeated reload/backlog limits and the broader generator/design/storage/travel/gameplay
qualification remain open.

## Component restoration now yields between providers — 2026-10-20

Startup and reload no longer execute all addon restoration in one uninterrupted
scene-thread call. The terrain facade holds the loaded result, and the persistence
coordinator restores providers in registration order with a configurable 1000-us
cooperative budget. World readiness, initialization and snapshot-restored notification
are published only after every provider finishes. Prepared native data remains owned
through the barrier. Legacy synchronous restoration remains available.

Captures during partial or failed restoration return an invalid epoch with no sections.
A second reload is rejected while restoration is pending. Shutdown during this phase
blocks snapshot writes before the backend captures shutdown state, preserving the
previous canonical save. Missing/failed provider callbacks mark restoration failed.

Targeted tests cover ordered yielding, no repeated provider calls, failure handling,
partial/failed capture rejection, publication gating, repeat-reload rejection and
shutdown protection. The integrated readonly regional reload restored components over
**8 frames**, with largest restoration slice **8.307 ms** (structures alone: 8.215 ms).
Water targeting/quantities, retirement cleanup and map-cache reuse passed. A separate
fresh-process full checkpoint comparison matched settlement blocks, all furnishings,
roads, residents and player position. Canonical save SHA-256 unchanged. Evidence:
`evidence/component_restore_budget`.

**Still open:** provider calls are atomic; this budget cannot preempt a slow provider.
Reload initiation remains synchronous and variable: this run measured 30.649 ms, with
23.510 ms in ground-cover reset. Do not present the component barrier as proof of
hitch-free world loading or sustained 60 FPS. Further lifecycle qualification must
include reset handlers, individual heavy providers and repeated loading/backlog limits,
alongside the broader generation, settlement, storage and gameplay gates below.

## Terrain reload payload retirement is budgeted — 2026-10-20

Profiling separated immediate terrain deactivation from releasing retained CPU mesh
arrays/collision dictionaries. In the baseline, record release took **7.386 ms** of
**8.124 ms** terrain retirement. Reload now retains the detached tile, staging and
preparation payloads in the existing retirement queue before clearing active ownership.
Old nodes are still hidden and collision-disabled immediately. Detached dictionaries
are released between entries under the same per-frame budget as old scene nodes;
shutdown also clears any outstanding payloads.

The readonly integrated regional-world check at 1920x1080 fullscreen passed: old
terrain roots were hidden immediately, populated reload completed, all retired nodes
and payloads drained, water quantities/targeting survived, and map cache reuse remained
correct. Terrain retirement measured **1.509 ms**, down from 8.124 ms. Largest observed
retirement slice was **2.939 ms**: this is cooperative scheduling, not a preemptive
hard bound on freeing an individual entry. Evidence: `evidence/reload_terrain_payloads`.

**Remaining qualification:** total reload initiation was 19.829 ms and result processing
25.840 ms in this run; other stages varied upward (including ground-cover cleanup and
component restoration). Do not claim an overall 60 FPS reload guarantee from the
terrain improvement. Larger payloads, accumulated retirement backlog, repeated travel
and variable component-restoration costs remain relevant to the wider loading budget.
No save format, terrain generation, density, vegetation amount or gameplay rules changed.

## Native whole-collection vegetation reset — 2026-10-20

Reload initiation is now instrumented separately for handlers, ground cover, trees,
terrain retirement and backend submission. The initial check measured 11.060 ms in
ground-cover reset: it removed each cell/species separately, repeatedly rebuilding
the same native render groups. Ground cover now clears each species collection once
through `NativeStaticBatch.clear_instances`, then clears interaction cells and
coordinator metadata. Meshes, materials, LOD/shadow settings and saved removal edits
are retained. No vegetation density reduction is involved.

Native clearing releases complete pages without repairing per-item indices that are
all being discarded, clears collision/render indices and appearance records, and
publishes one mutation. It refuses protected objects, paging ownership and active
region transfers. Empty clearing is idempotent. Native tests verify protected-state
rejection without partial changes, complete render accounting, no leftover page nodes,
exact revision behavior and repopulation using the original asset/IDs. Existing
ground-cover streaming tests pass, including deterministic regeneration, reverse
responses, failed-wave recovery and reset cleanup.

At 1920x1080 fullscreen, final integrated reload passed with ground cover at
**6.475 ms**, down from **11.060 ms**. Reload initiation measured **21.328 ms**;
an intermediate run was 17.352 ms, illustrating that total reload remains variable.
Final terrain retirement was **9.940 ms**, tree cleanup 2.433 ms and result restoration
13.033 ms. Water interaction/quantities, component restoration, retirement cleanup and
map cache reuse still pass. Debug/release structures binaries rebuilt; canonical save
SHA-256 unchanged. Evidence: `evidence/reload_bulk_cover`.

**Not closed:** the whole reload path is not yet within a 16.67 ms frame budget.
Terrain retirement and remaining ground-cover metadata/native destruction are
synchronous; they need bounded lifecycle work if larger worlds grow those costs.
These measurements do not qualify city-scale population or sustained travel. The
wider generator/design/storage/streaming gates below remain active.

## Populated-world reload retirement — 2026-10-20

A new integrated `world_reload_foundation.gd` check loads the saved regional world,
reloads it in the same process, and checks component restoration, water quantity and
identity, worker cleanup, republished water interaction targets, and cached map reuse.
It runs readonly at 1920x1080 fullscreen with vegetation, actors and vehicle fleet.

The initial populated reload exposed 25.441 ms in water restoration (34.997 ms total
reload-result processing). Installing the prepared store still discarded old native
regions and mesh/query buffers on the scene thread. The handoff now transfers those
retired containers, including frozen snapshot buffers, to its private store. A pool
worker destroys that state; the addon retains the handoff until task completion and
joins outstanding retirement tasks at shutdown. Live state remains on the scene
thread. Consumed/retired handoffs cannot be installed again.

Final measured water restoration: **3.649 ms**, including 3.555 ms clearing scene
references and **12 microseconds** native installation. Total reload-result processing:
**14.149 ms**. Water surface targeting republishes at the same location within 1 mm;
water quantities and content identity remain equal. All component maps complete and
the water map reuses its certified cache without source scans. Native ownership tests
pass; debug/release binaries rebuilt. Canonical save SHA-256 unchanged. Evidence:
`evidence/world_reload_retirement`.

**Next unresolved measured gate:** initiating reload itself still takes **23.582 ms**
(29.847 ms in the initial run), before the worker loads the snapshot. Terrain retirement
and vegetation reload handlers must be profiled separately before changing them. Scene
water-reference retirement is still synchronous (~3.6 ms here); larger saves and longer
runs are not qualified. This is not evidence of hitch-free reloads or sustained 60 FPS.
The wider generator, settlement, storage-capacity and streaming gates remain open.

## Water startup decoding moved off the scene thread — 2026-10-20

The existing loading worker now validates and decodes the complete native water
store, constructs its pending mesh/request queues, and extracts the validated lake
catalog. A single-use prepared object transfers those containers into the live store;
the scene no longer parses the full water packet twice. Serialized formats and static
bucket gameplay are unchanged. Synchronous restore remains supported. Prepared state
cannot be consumed twice; invalid input cannot replace live state.

The same saved regional world at 1920x1080 fullscreen reopened successfully. Startup
receive measured **12.561 ms**, including **0.069 ms** for the water component, compared
with the preceding 215–248 ms startup receive measurements. SHA-256 preparation remained
on the worker (126400 microseconds, zero scene-thread hash time). This is a measured
startup improvement on the current laptop, not a sustained frame-rate guarantee.
All four map layers reused their caches without initial source/visibility scans.
The integrated water test removed and restored the full world water store through a
worker-prepared handoff: all serialized water/contact bytes and map pixels matched.
The canonical world file SHA-256 remained unchanged. Debug/release DLLs rebuilt using
the existing prebuilt SDK. Evidence: `evidence/water_worker_restore`.

Still open: destruction of an already-populated old store and retirement of existing
render resources on an in-session reload have not been separately bounded. Decoding
still consumes worker time and temporarily retains the incoming decoded state alongside
any existing state. This work does not qualify large-world capacity, streaming tails,
city gameplay or terrain-fitting world design. Those wider gates below remain active.

## Block and water map caches now skip initial source scans — 2026-10-20

Both layers now use certified loaded-state identities before collecting geometry.
Block identities survive exact paging and are cleared by authored cell replacement,
resident-region replacement, combined prefab placement and unverified index changes.
Snapshot/storage/bootstrap validation installs identities before publication. Exact
collection transforms remain part of the cache key. Region metadata is captured only
after an early-cache miss. Publishing any overlay now releases its source resources,
including a checkpoint lease if a shortcut bypasses normal source completion.

Water snapshot restoration installs a content identity. Any existing snapshot
invalidation clears it conservatively, including water/contact changes. World load
prepares the content hash on the existing terrain loading worker. An immutable native
packet binds the hash to its exact bytes; main-thread restoration still validates
and decodes that packet before using its identity. The component persistence layer
supports optional native preparation without changing serialized save sections or
introducing an extra worker. Other providers keep their existing restore path.

An initial implementation added approximately 108 ms of hashing on the scene thread.
This regression was measured and corrected before committing: the final integrated
prepared-world check recorded 133845 microseconds on the worker and **zero scene-thread
hash time**. Native tests cover immutable packet ownership, invalid payload rejection
and identical prepared/ordinary identities. Direct synchronous restore remains a
synchronous compatibility API; world startup/reload use the prepared path.

At 1920x1080 fullscreen, fresh-process block cache lookup required zero source queries,
zero archived reads and zero visibility calls. Water likewise required zero initial
source queries and visibility calls. Temporary block placement/restoration and water
removal/restoration still changed/reproduced the expected pixels; stale certified
caches were not reused after edits. Completed block maps retain no source request or
checkpoint lease. Preparation reopened all four layers from caches with no block/model
archive reads, no water source calls and no visibility calls. Model identity shortcut
continues to apply. Canonical world SHA-256 remains unchanged. Structures and water
debug/release DLLs rebuilt. Evidence: `evidence/map_early_identity`.

**Still unfinished:** edited states can trigger a full overlay resurvey; these tests
still read 44 block regions across two edited states and scan water after removal.
Certificates are not yet refreshed on live saves, and equivalent snapshot/bootstrap
encodings can produce separate valid caches. Fine-detail maps, cross-layer height
ordering and large-world capacity/endurance remain open. Startup receive still took
about 215–248 ms in final checks, largely in water restoration; removing the hashing
regression does not resolve that existing loading cost. Do not treat the current
map milestones as whole-world performance or game-ready acceptance. Continue from
these measured loading/update limits while preserving the wider foundation gates.

## Certified model-map cache skips archive scanning — 2026-10-20

Validated full model snapshots and bootstrap metadata now install a native map
identity derived from their verified checksum. Exact unload/readmission, including
incremental transfer and cancelled transfer rollback, preserve it. Authoring changes,
asset reconfiguration and combined prefab transactions clear it. The certificate is
installed before publication, so synchronous authoring observers cannot leave an
incorrect certificate behind. No caller-facing certification setter was added.

The model overlay checks this identity before surveying any source geometry. Cache
identity includes exact binary collection transforms and prototype bounds alongside
the certified terrain identity and existing renderer version. Unchanged logical
content also preserves its runtime stamp across paging, avoiding unnecessary map
clears and cache reads. In-place mesh-bound changes invalidate the key even without
a collection edit signal. Edited/uncertified content uses the existing full survey
and content-hash path; it cannot use the saved-world shortcut.

Verification: snapshot and metadata certification, direct/incremental paging,
rollback, authoring removal/placement, prefab transactions, prototype mutation and
exact transform invalidation pass. In a fresh process opening the actual world at
1920x1080 fullscreen, the initial cached model map required **zero source calls,
zero archived model reads and zero visibility queries**. The subsequent temporary
placement and removal still refreshed/restored the correct pixels, and unsaved
changes could not reuse the old certificate. Those two edited states still read
324 archived regions in total; this is not an incremental-edit optimization.
The preparation/reopen gate passed with the canonical world checksum unchanged.
Debug/release structures DLLs rebuilt. Evidence: `evidence/model_map_identity`.

**Remaining:** block and water map caches still scan their sources (preparation
recorded 22 block archive reads and 506 water source calls). Apply safe early identity
lookup there next. Model certificates currently distinguish full-snapshot and
metadata bootstrap encodings, so different loading representations can create
separate valid caches. A save after authoring does not yet recertify the live model
collections; reopening a verified snapshot does. Local edits still trigger full
uncertified surveys. Fine map detail, cross-layer height ordering, capacity and
large-world/endurance qualification remain unfinished. These cache checks do not
resolve the separately recorded startup hitches or prove sustained 60 FPS.

## Model coverage integrated into the playable map — 2026-10-20

The M-map now draws a lilac model-object layer, using the same sparse native raster,
terrain-visibility worker, checksum cache and publication controller as block/water
cartography. This completes the source-to-live-map integration described below.
The region archive worker decodes model packets into survey objects; gameplay
paging cannot consume their dedicated completion channel. Pending, active and
completed cancellation release the correct model byte reservation and asset-specific
checkpoint reference. One archive request/decoded region is held per survey.

Native projection emits at most 256 samples per step, with continuation even for a
large model. It applies the captured collection transform and clips to map bounds.
Footprints under 4 square metres are omitted at this regional scale; larger objects
use conservative transformed bounding rectangles, not exact silhouettes. Terrain
above suppresses coverage. The 512-square layer is drawn below the block layer so
furnishings do not paint over buildings. These are regional navigation marks, not
an indoor map. Shared mesh bounds and collection transforms participate in runtime
invalidation. The content cache has its own namespace/folder, with 16 entries.

Verification: native projection continuation, transformed height, clipping and small
prop filtering pass. Archive checks cover model survey isolation from both gameplay
channels, worker decode and full reservation release on cancellation. In the actual
1920x1080 fullscreen saved world, model placement changed pixels, removal restored
identical pixels, unchanged reopening reused the layer, and closing an outstanding
survey released its request and lease. All model collections retained their original
storage/residency. The three-state run read 486 archived regions, made four visibility
calls (maximum 0.8163 ms), and wrote two caches. Fresh-process repeat hit all three
states with zero visibility calls. Before/edited images were inspected; the large
placed model appears as a readable lilac mark. Current small furnishings mostly fall
below the regional footprint threshold.

Preparation now requires the model map cached before publication; the saved-world
reopen gate passed with all four map layers cached. The canonical world root SHA-256
remains 872531c6141123460ec06132ffbf1ba2c75de5d0089d420f75220d625602717a.
Debug/release structures and world-runtime DLLs rebuilt using the pinned SDK.
Evidence: `evidence/model_map_integration`.

**Remaining map efficiency work:** content-key computation still scans source records
and reads archived model regions before a cache hit. Replace that repeated work with
validated region/asset identities, retaining exact invalidation for unsaved edits,
prototype changes and collection transforms. Local overlay updates, fine-detail
coverage, ordering by surface height across layers, capacity and large-world
qualification remain open. Current visibility tests concern terrain occlusion, not
exact mutual model/block occlusion. The integrated run also logged a startup receive
hitch around 258 ms; screenshots at 60 FPS are not sustained-performance proof.
The broader world foundation and world-art acceptance remain incomplete.

## Model cartography source verified against the generated world — 2026-10-20

NativeStaticBatch now exposes a revision-guarded survey index for resident and
archived model regions, captured collection transform and mesh bounds. A query
returns at most 32 transformed model bounds, using stable ID continuation rather
than rescanning records. In-flight region transfers explicitly report not ready;
unloaded regions and stale revisions are explicit. Unconfigured collections are
not ready. Metadata capture remains bounded by existing collection limits, not a
per-frame operation.

NativeModelMapRegion verifies the existing packet checksum, internal format and
asset identity, and produces identical bounds without admitting models to gameplay.
It is worker-owned and uses the existing model archive format. Bounds are local to
the collection and conservative axis-aligned extents after placement rotation and
scale, not exact mesh silhouettes. Consumers must also invalidate on prototype
bounds/collection-transform changes; edits to a shared mesh resource in place do
not necessarily advance the collection revision.

Native tests cover 70 rotated/scaled records, bounded continuation, resident/archive
equivalence, unloading, stale revisions, corruption, wrong asset identity and
retirement-in-progress. The actual generated world at 1920x1080 fullscreen yielded
995 models across 162 archived and 64 resident regions, with a maximum measured
batch query of 80 microseconds. Collection storage/residency and revisions remained
unchanged. Test reads used checkpoint leases and exact model tickets; archived
packet decoding ran on a worker. Debug and release DLLs rebuilt with pinned SDK.
Evidence: `evidence/model_map_source`.

**Next required work, not complete:** integrate model bounds with the live map's
native reduction, terrain occlusion and derived cache. Include transformed footprint
coverage and a sensible minimum map size so tiny furnishings do not swamp buildings.
Use the existing archive worker rather than one new thread per region in production.
Then verify actual placement/removal, distant archived coverage, cache reopening,
map closure/cancellation and visual readability. The test currently verifies the
source only; models are not yet drawn by the playable M-map. This is continuation
of the same map task, not acceptance or deferral of its unfinished integration.

## Building coverage integrated into the playable world map — 2026-10-20

This supersedes the source-only limitation below. The M-map now draws constructed
block coverage from both resident and archived regions. A dedicated archive worker
completion channel decodes one checksum-bound region at a time without admitting
it to gameplay residency or constructing meshes/collision. Closing an incomplete
map cancels its request and releases its checkpoint lease; normal paging cannot
consume its replies. Archive cancellation accounting now includes queued requests
cancelled before worker execution.

Water and blocks share a native sparse regional raster and bounded survey
orchestration. Blocks use 512-square coverage (approximately 3.9 metres per pixel),
with terrain occlusion in batches of 16 samples. The raster admits up to 262144
subcell samples and fails explicitly at capacity. Source calls yield cooperatively
after about 1 ms; allocation growth and full pixel publication are not yet qualified
at the maximum capacity. Runtime drawing adds one building texture draw.

Derived block caches are checksum validated, keyed by certified terrain identity
and deterministic block-source content, and limited to 16 entries (about 16 MiB).
Cache hits avoid visibility jobs but still scan/read source data to establish its
identity. Preparation now requires the building layer to be ready and cached.
No authoritative world format changed; tests used a read-only snapshot.

Verification: native archive isolation/cancellation, sparse raster and 256/512 cache
checks passed. In the actual 1920x1080 fullscreen world, archived coverage did not
change block residency; a temporary 144-block platform changed map pixels and
restoring the original region reproduced the original pixels. Fresh-process tests
hit all three block state caches with zero visibility queries. Water regression
also passed with zero visibility queries. The prepared-world reopen passed with
22 archived block reads, a cache hit and zero block visibility queries. Before,
edited and distant-neighborhood screenshots were inspected: useful regional
coverage, not exact building outlines. Evidence: `evidence/building_map_integration`.

**Still open:** model-only structures, finer detail, local incremental overlay
updates, avoiding full source traversal on cache hits, and large-city/capacity
qualification. A startup receive hitch reached about 197 ms in this run; the edited
map capture showed 37 FPS. These checks do not certify steady 60 FPS, old-laptop
thermal behavior, world-art acceptance or a game-ready foundation. The generator,
location variety, complete travel/interior coverage, storage endurance and broader
runtime limits listed in this document remain required work.

## Building-map source includes unloaded world regions — 2026-10-20

Native block cartography now exposes a metadata index covering both resident
chunks and checksum-only unloaded regions. The index carries a mutation revision
and world transform; a live region query rejects a stale revision or explicitly
reports unloaded data instead of treating it as empty. The index is a bounded
metadata capture (existing resident/unloaded store limits), intended for survey
start/invalidation, not every frame.

Each column query visits at most one occupied 16-cube chunk and returns no more
than 256 local-space samples; empty chunk positions are skipped within the
64-chunk region bound. Samples use the highest occupied cell in each chunk column
and the actual shape height at its centre, including slabs, stairs and slopes.
These are cartographic samples, not exact silhouettes or already occlusion-tested
building footprints.

NativeBlockMapRegion decodes one existing checksum-bound archive packet off the
scene thread and exposes the same bounded queries. It neither admits the region
to gameplay storage nor builds rendering/collision. No new authoritative save
format is introduced. Existing archive checkpoint leases retain the requested
versions while a worker reads them.

Verification: signed coordinates, highest columns, cube/slab/stair/slope heights,
resident/archive equivalence, stale revisions, explicit unloaded state and corrupt
packets pass. The actual saved world survey included 22 unloaded and 6 resident
regions, yielding 11096 column samples; maximum measured query was 49 microseconds.
Block storage/residency statistics and mutation revision remained unchanged.
Debug/release structures DLLs rebuilt against the pinned SDK. Evidence:
`evidence/building_map_source`.

**Not yet complete:** this source is not yet drawn on the M-map. Native reduction,
terrain occlusion, cached publication and map invalidation still need integration.
Free-standing model-only structures are not covered by block columns. Existing
building-footprint/finer-map and broader foundation gates remain open. No final
visual or large-city performance acceptance follows from the source checks.

## Actual water integrated into the M-map — 2026-10-20

The playable map now draws a separate native-reduced live-water overlay instead
of painting generated basin circles into terrain. Base survey version 3 invalidates
old blue terrain caches. Actual water removal clears blue coverage; snapshot
restoration reproduces identical coverage. Native reduction keeps the highest
sample per 3.90625 m subcell and filters it against actual terrain above, then
reduces 2x2 coverage to the 256-square map. This is approximate regional coverage,
not exact shoreline geometry. Rendering uses one additional texture draw.

Source orchestration admits at most four four-region calls per frame and yields
after approximately 1 ms. Each visibility job has at most 16 points on the ordered
terrain worker. World epoch, terrain revision, water revision and store identity
invalidate work; stale replies cannot publish. Native raster working storage is
bounded (under 5 MiB excluding Godot images/textures). Completed runtime maps are
reused while these identities remain unchanged; closed maps submit no new work.

The water layer has its own checksum-validated, content-keyed derived cache,
limited to 64 entries (about 16 MiB). Its identity combines certified terrain state
and native compatibility, a water-map version, and the deterministic source-point
hash. Unsaved water cannot overwrite the terrain map cache. Unsaved terrain is
surveyed but does not acquire a certified water-cache entry. Disk I/O runs on a
low-priority worker; corrupt/mismatched data uses the normal recomputation path.
Preparation now requires the actual water map to be cached before publication.

Verification in the saved v14 world at 1920x1080 fullscreen: original water,
complete removal, restoration and unchanged reopen pass. Approximately 103000
source samples reduce to 1199 visibility candidates. The uncached integrated run
recorded a maximum 0.268 ms source call and 3.753 ms visibility job. Fresh-process
cache reuse passed for original/empty/restored states with three cache hits and
zero visibility queries. Preparation reopen passed with both map caches reused
and exact settlement blocks, furnishing, roads, resident and spawn signatures.
Base cache corruption/identity tests and native raster validation pass. Debug and
release DLLs rebuilt with the pinned prebuilt SDK.

Inspected before/after overview images confirm blue lake coverage is removed;
public named basin/destination markers intentionally remain. A first script-name
collision and an empty-buffer hashing diagnostic were caught and corrected;
retained failed run summaries and subsequent clean evidence are in
`evidence/live_water_map`. Original authoritative saved-world bytes are preserved.

**Still open:** finer zoom, building footprints, large-population/world limits and
the broader foundation gates below. Cold water maps still incrementally traverse
stored water once; disk hits avoid terrain visibility queries, not that source
scan. Water edits currently invalidate the whole small map layer rather than only
local map tiles. Highest-sample subcells can miss smaller lower exposed water
beside covered water; this approximation must not be called an exact shoreline
survey. This work does not establish ocean-scale or older-laptop performance,
steady 60 FPS, or final world-art acceptance. Water gameplay remains unchanged.

## Water-map height and terrain occlusion established — 2026-10-20

Native water cartography now has a separate bounded surface-sampling query. It
uses cached contact profiles and stored amounts to locate wet column centres;
occupied voxel upper bounds are not treated as water height. Each call visits
at most four regions (256 samples), with the existing cooperative 500 microsecond
stop after a region. Unready contacts are reported explicitly and mutations
invalidate continuation. This changes neither bucket behavior nor save bytes.

The ordered terrain worker now accepts at most 16 water points per visibility
request, yielding a mask from actual edited density above those points. It checks
roofs/overhangs rather than relying on generated terrain height. It has the same
queue admission guards as terrain-map patches, and returns epoch/revision for
stale-result rejection by the eventual map consumer.

Actual saved-world check: 102728 surface samples; sampled points touch stored
water; maximum native source call 204 microseconds; one integrated 16-point
visibility request 1.1339 ms. Mutation rejection, removal accounting and existing
storage restoration checks pass. Native occlusion test rejects covered/solid
points, admits them after roof excavation, preserves the result through storage
restoration, and rejects invalid/oversized input. Debug/release DLLs rebuilt using
the pinned prebuilt SDK. Evidence: evidence/water_map_visibility.

The first occlusion fixture incorrectly expected a sphere brush to excavate a
segment; the retained failure was corrected by explicitly excavating overlapping
spheres through the roof. No production algorithm was changed to satisfy it.

**Still open:** M-map live-water raster accumulation, live-water cache identity,
removing obsolete generated-water colours, building footprints and finer zoom.
The current visible map remains explicitly labelled as a base-water survey. The
new source samples are cartographic point samples, not an exact mesh silhouette;
thin shore fragments between samples need a deliberate raster coverage policy.
No graphical water-layer quality or whole-world performance acceptance is claimed.

## Native water-map source established - 2026-10-20

The existing native regional water store now exposes a bounded cartographic
column survey independent of visible mesh residency. Each call visits at most
16 regions, with a cooperative 500 microsecond stop checked after each region.
At most 1024 occupied-column records are returned per call. A monotonic store
revision rejects continuation after any authoritative/cache mutation; restart is
explicit rather than silently combining old and new water. This introduces no
water flow, changes to bucket rules or changes to snapshot bytes.

Actual saved v14 world verification traversed all stored regions in 506 calls
at a four-region budget, returning 104588 occupied column records. The maximum
observed native call was 13 microseconds on this machine. Summed quantities exactly
match the stored total. Removing real water invalidates an in-progress cursor;
a fresh survey reports exactly the reduced amount. Saving/restoring reproduces
identical columns and amounts. Invalid budgets/cursors are rejected. Evidence:
evidence/water_map_source. The existing connectivity check also passes.

This is the native source dependency, NOT completed live water on the M map.
Columns describe conservative occupied 0.5 m voxel upper bounds, not exact rendered
surface height or terrain visibility. Next accumulate them into a bounded map
layer, combine with terrain surface visibility, invalidate on water mutations,
and qualify cache identity/reload before removing the base-water disclaimer.
Do not render the raw columns as final lake shapes or reveal underground volumes.
The test intentionally collects columns for equality checking; production must
consume incremental batches rather than rebuilding a full record list per frame.
Building map coverage and existing world-foundation gates remain open.

## Prepared cartography reaches gameplay copies - 2026-10-20

The ordinary complete-world workflow now warms edited terrain cartography during
its fresh-process verification phase, after terrain publication establishes the
exact content identity. It uses the same bounded map pipeline as gameplay and
requires a completed cache hit/write before publishing the playable world. This
moves initial modified-terrain surveying out of the first gameplay map open.

World cloning opportunistically carries the derived map cache to the new slot.
It validates magic, exact length and checksum before copying; runtime still checks
the exact terrain/code identity. Missing/corrupt cache never blocks a valid world
clone. Existing destinations remain untouched, and clone-side retention uses the
same 64-entry dedicated cache bound. Tests cover valid copying, existing-save
preservation, corrupt-cache fallback, retention and unrelated-file preservation;
all three pass. All fifteen preparation/cancellation tests also pass.

Fresh seed42/generator13 preparation of foundation_map_42_20261020 passes creation,
reopen and cache publication (150 patches, one write). A further independent review
copy starts a fresh gameplay process and opens its map with one cache hit, zero
writes and zero native terrain patches. Its pixel digest matches the prepared
terrain survey. Evidence: evidence/prepared_map_cache. Play Regional World
Review.cmd now creates v14 from this prepared source; versions1-13 remain intact.
This changes cache preparation, not world layout, assets or save format.

The remaining map layers are still required: live water coverage and building
footprints, with explicit scale/zoom limits. The world-quality, storage-growth and
sustained-performance gates elsewhere in this document remain open. A cache hit
is not proof of overall runtime performance; world startup still shows loading
hitches. Continue the remaining representation scope before unrelated feature work.

## Persistent edited-map cache - 2026-10-20

Edited terrain map pixels now persist in a disposable checked cache. The ordered
terrain worker supplies the exact certified terrain snapshot digest plus native
compatibility fingerprint; the UI does not guess identity from seed/revision or
read mutable terrain on another thread. Unsaved mutations invalidate certification.
Reads/writes/checksums run on a low-priority file worker, outside the terrain worker.
One in-flight IO job and one entry per slot; the dedicated cache keeps at most 64
completed entries (about 16 MiB), with temporary-file rename publication. Existing
world files are never cleanup targets. Header identity, exact size and SHA256 are
validated; a miss/corruption falls back to the bounded native patch queue.

Checks cover wrong identity, corrupted bytes, truncation, atomic replacement,
invalid input and bounded eviction. Actual combined-world checks use an isolated
copy of v13: cold open surveys 150 patches and writes once; a fresh process reuses
exactly identical pixels with zero native patches. Unsaved excavation changes six
patches but preserves the saved cache; a fresh process recovers the original map.
Then ordinary durable save gives the edited map a new identity, replaces its cache,
and another fresh process recovers exactly those new pixels with zero resurvey.
Pixel hashes are compared in evidence/edited_map_cache/pixel_identity.json.

The first unsaved-edit check exposed a missing in-memory identity reset. Revision
checks already prevented a disk overwrite; the stale identity state is now cleared
on invalidation, and the rerun passes. Failed and successful evidence are retained.
Warm full test process duration is about 19 s including world loading; this is not
map-cache IO latency, a speedup claim or thermal proof. No world-generation, save
format or native terrain algorithm was changed in this pass.

The cache currently warms on first map use, not during offline world preparation.
Continue this map scope with preparation-time warming/clone reuse, live water-field
coverage and useful building footprints. The water overlay remains explicitly the
base survey, and 7.8 m raster resolution still limits visible small changes. Native
surveys for a cache miss remain bounded rather than synchronously surveying the
whole world. Overall world generation/design, storage scale, sustained travel and
remaining gameplay qualification gaps are still open.

## Edited terrain on the player map - 2026-10-20

The M map now overlays native surface surveys of modified terrain on its cached
base landscape. Saved modified-column metadata seeds a bounded 4096-tile dirty
set; published terrain bounds invalidate only intersecting tiles plus a shading
halo. Each worker request covers at most 4x4 pixels (36 columns including halo),
one request in flight. It waits behind existing terrain work and is admitted only
without active edits/brushes and with a small queue. Closing the map stops new
requests. Epoch/revision checks reject obsolete replies; reopening retains the
current image instead of surveying the whole world again. All density sampling
runs in C++; GDScript manages the bounded presentation queue and image upload.

Native tests cover excavation changing pixels, exact reproduction after terrain
serialization/restoration and rejected out-of-bounds/oversized patches. The actual
v13 world initialized 150 patches and updated six after one 24 m excavation, with
no base-map rebuild or streaming-focus movement. The complete check passed in
22.1 seconds including world loading. Native patch microcheck was about 3.1 ms;
maximum observed integrated patch was 7.39 ms on the current laptop. This cost is
bounded work, not a hard millisecond guarantee on older hardware.

Existing map control checks pass: M/Escape, pan/zoom, equipment/input isolation,
public-only destination labels, exact saved road widths and reopen reuse. Short
120-frame samples: map-open p95 16.894 ms/max 17.030 ms, closed-after p95 16.860 ms/
max 17.044 ms at 1920x1080 fullscreen cap60. These are not endurance or thermal
proof. Initial world restoration still has loading hitches. Evidence and inspected
map images: `evidence/edited_world_map`. The excavation is a subtle topographic
change at regional scale, not a detailed excavation diagram.

Still required in this same representation work: persistent edited-patch cache
keyed to authoritative saved content, live water-field coverage, and representation
of constructed building footprints/placed objects where useful at map scale.
Water remains explicitly labelled as the base survey, not current bucket state.
The 256x256 raster resolves roughly 7.8 m per pixel, so subpixel edits cannot be
promised visible; zoom magnifies the survey rather than resampling detail. This
closes the missing terrain-edit update path, not the complete world-map requirement.
Next continue cache identity/persistence and remaining layers before changing scope.

## Connected cellar access and durable-close correctness - 2026-10-20

The combined-world player now has an authored 1.5 m footpath from the western
arterial around the cellar cottage to its entrance. It is prepared in the same
protected plan as the cellar, before building placement, then stored with the
road/path catalog. Seven generator seeds pass connected path geometry and base
terrain height samples at one-metre intervals across centre and edges; native
anchor serialization also passes. This is a fixed location recipe, not a claim
of arbitrary-lot path planning.

The first complete bake exposed a storage mismatch: terrain editing permits narrow
paths but native road-anchor storage only accepted widths >=4 m. The resulting
addon capture failed and fresh-process verification rejected the staged world;
no review world was published. Native anchor validation now accepts widths >=1 m,
matching the existing minimum terrain half-width of 0.5 m. Binary layout is unchanged;
existing road persistence and catalog limits still pass. Debug and release DLLs
were rebuilt against the pinned prebuilt SDK. Invalid/nonfinite/out-of-range widths
remain rejected.

That failure also exposed misleading graceful-close success: shutdown_after_edits
reported settled edits even when its final save failed. It now requires successful
persistent publication as well as settled edits. Disposable/read-only worlds still
close without writing. A 17-check shutdown regression includes deliberately invalid
addon bytes and proves both failure reporting and unchanged canonical file hash.

New foundation_cellar_42_20261020 passes full creation and fresh-process reopen.
Its saved path entries restore exactly. The real player walks from the arterial,
climbs the cottage stairs, opens the door, descends into the cellar, climbs back,
and returns to the street without intermediate teleports. The full route takes
about 58 seconds including loading at 1920x1080/fullscreen capped60. This is not a
frame-time benchmark: initial water restoration still reports a >200 ms loading
hitch and the existing sustained-performance requirements remain open.

Inspected overview, approach and ladder images show the connecting path and intact
entrance/interior surfaces. Cottage repetition, simple materials, sparse interiors
and broader landscape quality remain unfinished; these images are not world art
acceptance. Evidence, including the rejected bake, is in
`evidence/cellar_connected_access`. Play Regional World Review.cmd now creates a
separate v13 copy. Versions1-12 and original player saves are preserved; original
southern_mixed_42_20261018 SHA256 remains 3a76b6fa3e86aecf6c529263d22cf59174d73644dcb67d21b8332c4048ed4995.

Next foundation work remains the edited-world map representation and the broader
world qualification gaps (other road/junction and entrance topologies, multiple
complete seeds, storage growth/failure recovery and sustained populated travel).
Connected mine and cellar circulation now have direct integrated evidence; they
must not be relabelled as finished location design or full gameplay coverage.

## Connected mine route and parking correction - 2026-10-20

A full route from the eastern arterial exposed a real generator defect missed by
entrance-only tests: the parked vehicle overlapped the six-metre mine approach.
Collision diagnostics identified the Car body. The mine recipe now places it ten
metres farther into a widened parking apron, outside the access corridor. No
runtime hot path, storage format or native meshing change was needed.

Seven seed layouts pass transformed-chassis corridor clearance checks. Newly
prepared seed42/generator13 world foundation_access_42_20261020 passes creation
and fresh-process restoration. In that world, the native player walks from the
arterial through the mine entrance, both underground branches, and back to the
arterial: all twelve waypoints pass, with 3796 grounded ticks out of 3801. The
short stall check reports the blocking collider instead of waiting a full minute.
Evidence: `evidence/mine_connected_access`. Raw runner metadata retains a mistaken
completion-token failure; the separate assessment verifies the actual test token,
zero exit, clean diagnostics and complete trace without hiding that mistake.

Play Regional World Review.cmd now opens a separate v12 editable copy. Older
review worlds and original saves remain intact. This fixes newly generated worlds;
existing player vehicle positions are intentionally not overwritten.

Images inspected: entrance overview and underground workings. They establish
neither art acceptance nor an interesting finished mine: the entrance remains a
plain large frame and underground branches need authored purpose/detail. This
walk is a connectivity check at 1920x1080 fullscreen capped60, not a performance
benchmark or sustained-60 claim. Connected cellar access, remaining building and
junction topology, multi-seed integrated qualification, map edit representation,
world storage growth and sustained populated travel remain required foundation
work. Do not replace those with unrelated item or vegetation polish.

## Connected access and tower ground-floor correction - 2026-10-20

New actual-world checks start at the regional arterial, follow saved street
connections, climb entrance steps, open the door and enter a building without
intermediate teleports. Representative western, eastern, northern and southern
routes pass with default model paging. The test splits street segments at joining
points; its initial endpoint-only northern graph failure is retained as a test
limitation, not a generator defect. Old southern/northern entrance tests now wait
for destination residency before discovering doors. All four southern approaches
and entry/exit checks pass with paging.

Inspection exposed a real tower defect: the reusable upper-floor opening also
existed at ground level, exposing terrain and grass inside. Furnished towers now
fill those twelve ground cells with the existing slab material. Upper openings
remain unchanged. Native prefab checks cover 2/3/4/16 storeys. New seed42 world
foundation_42_20261020 was fully prepared and reopened through the ordinary
workflow. Its tower ascent/descent passes, and matching interior imagery confirms
the ground opening is closed. Runtime batching and terrain formats are unchanged.

Play Regional World Review.cmd now uses a separate v11 copy of that new world.
Versions1-10 and source/player saves are preserved; the launcher dry run was checked.
No automatic retrofit of existing edited buildings is attempted. Evidence:
`evidence/connected_world_access` (including pre-fix hole and regenerated interior).

Coverage remains limited: one connected representative entrance per outer location,
all four southern door approaches, and one tower's upper-floor route. This does not
qualify every building, basement/mine circulation, all junctions or multiple seeds.
Location design still needs meaningful interiors/variety and landscape transitions;
the plain tower interior is not art acceptance. Next address those remaining
connected-world and generator requirements, retaining the world-quality standard.

## Continuous vehicle travel with default paging - 2026-10-20

The real native car drove the saved seed42/generator13 central-west arterial at
1920x1080/fullscreen capped60, with default model paging, vegetation, actors and
fleet enabled. No pose corrections after initial staging/entry. A disposable
read-only clone preserves the source save. No collision streaming holds occurred.
Exact distance, speed, frame intervals and final stopping position are recorded
in `evidence/vehicle_default_travel/vehicle_paved_stop`.

The original travel test falsely accepted a stop beyond the road: 104 m braking
from approximately160 km/h overran its 85 m stopping allowance, ending20 m beyond
the arterial endpoint on grass. Retained diagnostic image/data expose the error.
The test now begins braking150 m before the endpoint and requires final corridor
containment plus native saved-surface support validation. Slow frames and collision
hold runs are recorded. Separate saved-terrain sampling passes228 points across
three lanes on each of the four arterials. That root-support check is not a mesh,
road-shoulder or navigability proof for those other three roads.

The corrected final image was inspected: vehicle on asphalt, buildings and vegetation
present. Western location remains visually unfinished: repeated cottage massing,
sparse landscaping and unresolved arrival/road-end design. Do not accept that as
world quality. The drive is one straight arterial, not junctions, turning, all-site
collision coverage, save-during-driving or endurance. Those gaps remain explicit.
Next finish the connected-world approach/entrance checks and generator design
requirements, retaining performance sampling on those actual routes.

## Regional model loading is now the normal world path - 2026-10-20

Native transfer preparation now advances directly into bounded transfer work in
the same tick. Previously it forced another frame even with budget remaining.
The shared operation, 500 us, 256-record and 64 KiB budgets still apply; the new
fall-through explicitly rechecks the operation guard. Both native variants built.
Scheduler (42), focus (24) and real paging lifecycle (23) checks pass. The focus
test's stale 8-operation assertion now matches the existing 16-operation adapter.

On the same 995-model populated world, northern arrival improved from 961 ms to
660 ms, south 684 to 483 ms, return 535 to 401 ms. Subsequent real edit/save and
fresh-process reopen pass, with northern arrivals 694/692 ms. All nearby saved
transforms, 128 m render readiness and local collision remain required at release.
Normal launch now enables paging; --no-model-region-paging remains a diagnostic
fallback. Offline preparation already explicitly uses full residency for complete
signature validation. The default-path four-stop route also passes. Evidence:
`evidence/model_default_arrival`. The source save SHA-256 is unchanged; only the
named disposable clone contains the intentional stairrail edit.

This closes opt-in-only model residency and the short-route arrival blocker. It
does NOT close strict frame-time, high-speed predictive arrival, full resident-memory
bounds, storage growth, or sustained performance gates. Measured post-arrival
frame maxima across the edit/reopen checks were 16.7-20.4 ms; earlier larger spikes
remain in evidence. Selection scans and native work caps still apply. Models pinned
by edit history and retirement in progress can remain resident beyond the radius.

Next: qualify continuous world travel with production player/vehicle collision and
attribute frame outliers, then connected generated-location/multi-seed acceptance.
No world-quality approval follows from this engineering check. Earlier opt-in
statements below describe historical state and are superseded here. To regenerate
the test manifest with full residency, explicitly pass --no-model-region-paging;
normal runs now validate paged data against that manifest.

## Durable saves no longer occupy the terrain worker - 2026-10-20

Compound saves freeze their sections on the ordered terrain worker, then publish
on one bounded background job. New saves receive backpressure while it is pending.
Reload/reset and shutdown join publication before replacing state or releasing the
archive lease. Completion certifies derived caches only if the captured terrain
revision and component epoch still match. Native validation, checkpoint retention,
checksums, verified root publication and backups remain in place.

In the populated-world 360 m flight/save check at 1920x1080/60 FPS, height queries
completed in 17-51 ms and mining published in about 116 ms while disk publication
was still pending. Save-window frame maxima were 16.9/17.0 ms. Controlled publication
barriers pass 15 checks; native model paging's real manual/autosave/reload/reset/
shutdown lifecycle passes 23; combined bucket/mining/building save/reopen passes.
Evidence: `evidence/publication_async`. No player save was modified.

Limits remain explicit: component materialization/validation takes 109-176 ms on
the terrain worker before publication; cold main-thread capture is still around
8-9 ms. Baseline flight had a 33.5 ms frame outlier. These short checks do not prove
sustained 60 FPS, walking/vehicle collision readiness, old-laptop thermals or world
capacity. Publication overlap is verified; all save latency is NOT resolved.

Next foundation gate: populated regional model arrival and repeated travel with
editing/saving, then connected generated-world routes and multi-seed landscape
acceptance. Model paging remains opt-in until its arrival/frame bounds pass. Do
not let optional cosmetic work displace the coverage table below. Historical
sections record previous limitations; this section supersedes the synchronous
publication blocker described immediately below.

## Direct section publication removes temporary archive round-trip - 2026-10-20

The terrain save worker passes sections directly to the regional archive adapter.
The base archive exposes the SAME name/type/count/size validation used by encoding;
validation happens before any region-store changes. The adapter copies the input
mapping, commits checkpoints, and encodes/checksums only the final root. Existing
packed-archive publication remains supported. Final checksum validation, flushed
readback verification, backup retention and atomic root replacement are unchanged.

Cold/warm write phases measured 0.84/1.00 seconds versus 1.14/1.28 seconds before;
the temporary encode (~140 ms) and decode (~137 ms) are removed. Native archive,
87-check regional archive, 34-check retention and actual gameplay compound
save/reopen checks pass. An old catalog test now checks current v2 bytes and explicit
v1 compatibility. Both native variants updated. Evidence:
`evidence/publication_direct_sections`.

Blocking remains OPEN: serialization/validation plus durable publication still
occupy the terrain worker for roughly 0.95/1.09 seconds in this short check. Next
isolate durable publication on a bounded worker with explicit ordering/barriers
for repeated saves, reload and shutdown; verify mining/streaming can progress
while a save is pending. Do not remove integrity work to claim a latency pass.

## Checkpoint retention scans unified - 2026-10-20

Native publication profiling identified pre/post-publication checkpoint cleanup
as 0.94-1.27 seconds of repeated root validation. Block and model checkpoint
references now come from one validated read of each canonical/backup root per
sweep, retaining lease protection, missing-checkpoint and corruption rejection.
Cold/warm archive publication fell from 1.44/1.77 s to 0.97/1.11 s on fresh clones
of the same populated world. Full write stages remain 1.14/1.28 s. Native archive
and checkpoint-retention tests pass, including corrupted backups and partial
resident state. Both native builds updated. Evidence: `evidence/publication_root_scans`.

Publication blocking remains OPEN. Next remove redundant intermediate archive
encoding/decoding or isolate publication while retaining the ordered durable
commit contract. Remaining profile: ~140 ms intermediate encode, ~137 ms decode,
~134 ms final encode, ~200 ms durable root publication and ~620 ms retention scans
on a warm save. Do not treat these short smooth save windows as complete streaming
or mining latency qualification. Baseline frame outlier remains ~35 ms.

## Actual flight-and-save attribution - 2026-10-20

A disposable clone of the populated world travelled 360 m using native player
flight at 1920x1080/60 FPS, with cold and warm normal disk saves. Production
full-resident model settings were used (paging still opt-in). Main dispatch was
7.6/2.1 ms; save-window frame maxima were 16.9/17.0 ms after routine console writes
were made opt-in (`--verbose-world-events`). Errors still log and all status text
still displays. Test callbacks no longer print inside measured frames. The initial
38 ms completion sample included both game and test synchronous logging.

Do not declare global frame stability: baseline maximum was 34.2 ms. More
importantly, archive publication occupies the terrain worker for 1.38/1.79 s;
packing adds ~130 ms and component serialization/validation 84-103 ms. This can
stall streaming or edits even while rendered frames remain smooth. Next inspect
regional/archive publication stages and eliminate unnecessary repeated work or
isolate durable publication from terrain work, preserving atomic roots, backups,
checksums and save ordering. Flight does not qualify walking/high-speed collision
or long-run performance. Evidence: `evidence/world_travel_save`.

## Cold water serialization moved to ordered world worker - 2026-10-20

Normal world capture now freezes native water records and shares immutable
terrain/building contact geometry. The existing terrain worker materializes the
payload before component validation and archive publication; no live water object
is read by that worker. Unchanged captures share the same frozen payload. Copied
records are released on the worker after serialization, retaining immutable bytes.

Actual populated-world main-thread capture is 8.5-9.0 ms cold, 0.46-0.56 ms repeated
(previous cold 19-21 ms). Worker serialization preserves the prior SHA-256. Later
live edits cannot change a queued snapshot. The 128 MiB conservative staging
reservation is finite, fails closed and recovers on release. Existing 64 MiB byte
cache bound remains. Actual compound bucket/mining/building save/reopen and manual
save ordering pass. Both native builds updated; format/gameplay unchanged.
Evidence: `evidence/world_capture_worker`.

This is not a sustained frame-rate guarantee: cold capture still consumes about
half a 60 FPS frame, worker serialization may delay queued work, and world size
scaling remains to qualify. Next measure actual save dispatch while travelling
and address the measured limiting stage. Full foundation coverage remains open.

## Unchanged world captures reuse immutable native snapshots - 2026-10-20

Water snapshot reuse now retains at most 64 MiB including catalog bytes, with
copy-on-write ownership for worker saves. Water quantity edits, mutable-region
access/creation, terrain/building invalidation, accepted occupancy patches and
successful restore invalidate it. Catalog identity must also match. No frame
polling or background simulation was added. The populated-world repeated capture
fell from ~21 ms to 0.46-0.49 ms; first captures remained 19-21 ms. Actual compound
save/reopen with bucket edits, terrain mining and partial buildings passes.

Cold/edited capture is still synchronous and remains unfinished. Next implement
bounded preparation or immutable worker serialization for those captures, then
measure real save dispatch while travelling. This cache alone is not proof of
sustained 60 FPS. Memory retention is explicit in native statistics. No gameplay
or archive format change; paging promotion and other foundation gates stay open.
Evidence: `evidence/world_capture_cache`.

## Save capture attribution and native serialization - 2026-10-20

Actual populated-world captures identified water serialization as the dominant
main-thread cost (59-77 ms for 36.9 MB). Replacing per-field extension API calls
with one writable buffer and explicit little-endian encoding reduces complete
capture from 61-78 ms to 21-22 ms in the paired check. SHA-256 remains identical.
Edited and unchanged snapshots roundtrip exactly; truncated restore is rejected
without changing live data. Both native builds updated. Evidence:
`evidence/world_capture_serialization/summary.json`.

This does NOT close the save-frame budget: 21 ms still exceeds a 60 FPS frame.
Next address bounded capture / unchanged section reuse with explicit mutation
invalidation, and measure actual save dispatch during travel. No water gameplay
or archive format change. Paging stays opt-in; arrival tail latency, the earlier
43.523 ms travel spike, storage growth, world-quality acceptance and sustained
whole-world performance remain open under the foundation register below.

## Startup autosave corrected; paging promotion withheld - 2026-10-20

Default-on compatibility checks passed model edit/save/fresh reopen and browser
create/reopen. Writable startup exposed autosave consuming loading time and then
blocking first travel (1932 ms). Controller now pauses automatic-save timing and
submission during loading; manual/shutdown saves remain. Offline generation
explicitly keeps full model residency for complete signature verification.
Fresh reopen still took 1103 ms north, so the one-second gate is not reliable:
production model paging remains opt-in. Evidence: `evidence/model_default_compatibility`.
Prior frame spike and main-thread save capture remain open. Next assess real
travel/loading and save stalls before promotion; do not weaken readiness.

## Short-route arrival gate passes - 2026-10-20

Native completed reads now advance through local stages within each tick. The
scene permits 16 operations while retaining 500 us/256 records/64 KiB budgets.
Two populated routes reach north in 972/966 ms, south 549/484 ms and return
633/667 ms, with exact nearby data, published pages, collision and retirement.
Evidence: `evidence/model_admission_stages`. This closes the recorded one-second
short-route gate, not a general latency guarantee. Prior 43.523 ms spike remains
open. Next normal-launch/default-paging compatibility and final save/reopen, then
combined travel frame attribution. Keep full world-foundation scope unchanged.

## Model admission scheduling improved - 2026-10-20

Automatic background retirement now occupies at most two of the eight native
transfer slots, preserving foreground admission capacity without larger budgets.
Actual north/south arrivals improved 1.782/1.195 s to 1.215/0.467 s in the first
comparison. Both modified routes preserve readiness/correctness; the repeated
route verifies eventual far-record retirement. Slower background retirement and
its temporary residency increase are recorded in `evidence/model_admission_priority`.
North still fails the one-second gate. Paging stays opt-in; next finish arrival
latency qualification and travel frame timing rather than weakening readiness.

## Nearby visual readiness implemented - 2026-10-20

Loading now waits for native model metadata admission AND published render pages
within the 128 m arrival extent. Actual four-stop populated route has zero missing
nearby models at release and local collision ready. Native edge cases, capture
replay and normal startup pass; both native builds updated. Evidence:
`evidence/model_visual_readiness`. Northern/southern arrivals take 1.745/1.249 s,
exceeding the earlier 1 s gate. Keep paging opt-in; next attribute and reduce native
admission latency without weakening readiness. Sustained performance remains open.

## Arrival collision gap corrected - 2026-10-20

Populated-world paging released the northern loading screen before nearby model
collision existed. Production now waits for native structure and vegetation
collision in a small departure box. Four arrivals pass. Evidence and retained
failure: `evidence/model_arrival_readiness`. Visual admission remains open: some
nearby records are still absent at release even when pending render uploads is
zero. Next add bounded native visual readiness over unloaded metadata and actual
published pages; keep model paging opt-in until that and arrival budgets pass.

# Playable world foundation - current contract

Updated 2026-10-20. This is the current priority and coverage register. Historical
PROJECT_PLAN entries are evidence, not a sequence of remaining instructions.
The objective is a coherent generated, persistent, efficiently represented world
that can be played and explored. No subsystem is accepted solely because its
isolated test passes. Unknown is not complete.

## Delivery order

1. **Generation and prepared loading:** one normal create/open path, seed and
   generator identity, prepared terrain/water/map caches, recoverable publication,
   cancellation and useful progress. Existing saves must remain unchanged.
2. **World representation and storage:** bound resident data as travel distance,
   edits, buildings and props grow. Verify normal default paths, distant edited
   representation, cache invalidation, quotas, disk reserve and recovery. Native
   model paging is still opt-in in demo/world.gd; block paging runs normally.
   Next substantive representation gate: the same populated saved-world route
   with model paging enabled, editing/save/reopen, and resident/arrival bounds.
   Do not enable it by default just because isolated pager tests pass.
3. **Connected world quality and gameplay:** finish regional roads/shoulders,
   entrances, interiors, stairs, basements/mine approaches and lake access in the
   generated world. Rare underground locations belong to POIs. Validate routes
   across multiple seeds, on foot and by vehicle, with real production collision.
4. **Scale and release:** mixed content with stated population/detail/distance;
   1920x1080 fullscreen 60 FPS, bounded CPU/GPU/memory/disk, recovery and endurance,
   followed by a clean-machine distributable build. Tests start short; endurance
   is for resource growth and thermal questions, not basic correctness bugs.

These stages overlap only when a dependency requires it. A visible defect stays
open with evidence; it cannot disappear by renaming the milestone. Stop isolated
visual tuning after unsuccessful bounded cycles and return to the world blocker.

## Current coverage and required completion evidence

| Area | Present in the actual project | Still required |
|---|---|---|
| Generator | Native terrain profiles; offline five-site composition with roads, buildings, POI undergrounds and lakes | Mostly fixed topology/palette; broader seed coverage and coherent landscape/design acceptance |
| Preparation | Staged creation, fresh-process verification, no-overwrite publication, progress and cancellation | Whole-route cache coverage; standalone workflow without local Python/toolchain |
| Player map | M map, content-checked persistent edited-terrain cache, bounded native patch updates, saved roads, destinations, pan/zoom/tracking | Live water, building footprints and finer zoom detail remain incomplete; see latest evidence above |
| Terrain and distant world | Native streaming and derived caches, local edits | Distant edits must remain visible; mining/travel tails and cache/resource growth are not fully qualified |
| Buildings and static props | Native blocks, batched props, furniture, doors/windows, storage, regional block paging | Detailed populated-world residency capacity; mixed interiors/approach acceptance |
| Roads and travel | Regional routes, local streets, normal collision loading, parked/drivable vehicles | All shoulders/junctions and high-speed arrival at declared speed; bounded repeated cross-world travel |
| Underground resources | POI mine/cellar, chambers, ore materials and gathering | Rare authored-location quality, circulation, excavation correctness and persistence on a combined route |
| Vegetation | Native sparse clustered distribution, species, harvesting, near shadows, distant LODs | Distant speckling/continuity, bulk-change continuity and combined resource budgets; density increase superseded by user's sparse direction |
| Water | Static volumetric fixed-unit bucket editing and persistence | Keep existing accepted scope; include in combined saves/travel/recovery checks, no new flow/spillage work |
| Player interaction | Inventory/toolbelt, crafting/storage, tools/durability and building | Connected gather/build/store/explore route, UI/input correctness across modes |
| Entities | Native stores, activation, two prepared residents and local behavior | Representative populations, navigation, animations, effects and bounded activation; stored count is not simulated capacity |
| Storage | Versioned snapshots, regional references, validation, backups and lifecycle barriers | Explicit authoritative/cache limits, disk failure/recovery, growth/compaction and large edited-world capacity |
| Multiplayer readiness | Stable identities and some command/storage boundaries | Authority/ownership audit before expanding systems; actual networking remains later work by user direction |
| Release/performance | Pinned native toolchain, local launchers, published 0BSD project | Clean installation/export, declared support, sustained 60 FPS and older-laptop thermal evidence |

## Explicit scope decisions

- No water flow or spillage; food/vitals remain deferred by user request.
- Networking implementation is later; authoritative ownership and replayable edits
  must still be considered now. No multiplayer capacity claim.
- Preserve sparse vegetation and existing models. Distant visual defects remain
  recorded, but AA experiments no longer displace world-foundation delivery.
- Hardware changes invalidate utilization comparisons. Use time/resource measures;
  unavailable older-laptop thermal testing stays unqualified.

## Evidence required to close a gate

Record the production entry point, world/seed, build, changes, shortest meaningful
check, inspected captures where relevant, save/reopen result, workload counts and
limits. A headless correctness pass is not rendered performance acceptance.
Retain failures. Keep the current human review launcher usable. Never overwrite a
player save to make it match a new generator recipe.

## Current change

Map preparation now uses the same native cartography/cache code as the M map.
New-world preparation requires persistence and readback before proceeding; existing
world cache preparation does the same without changing the canonical save. Cache
headers bind version, seed, generator and resolution to the checksum, so a valid
other-world cache cannot be accepted under a renamed file. This closes a small
prepared-loading gap, not whole-world baking or foundation completion.

## Populated model paging correction - 2026-10-20

Actual-world travel exposed missing prefab-only stair rails: the native history
registry omitted non-UI collections. All world model collections now participate.
995-model baseline, central/north/south/return exact nearby records, native journal
edit, normal save and fresh-process return pass. Original failures retained in
`evidence/populated_model_paging`. No source save changed. Next: destination model
collision/render readiness and measured arrival/frame bounds before default enable.

## Two connected settlements — 2026-10-20

Seed 42, generator 17, saved slot `two_settlements_paved_20261020`.
The terrain-fitting review launcher now defaults to version 4; versions 1–3 and
existing player saves remain intact. Twelve northern buildings connect by a
surveyed forest road to eight central cottages, shops and workshops with sidewalks.
The central recipe selects raw terrain within the same 2 m fill / 3 m cut limits.
Actual neighboring lot bounds and regional reservations constrain its placement.

Engineering: 352 combined terrain edits, 20 buildings; native foundation and road
probes passed. Seven northern seed plans still pass after the shared planner change.
Full bake/save passed in 84.43 s; separate-process reopen passed in 21.42 s with
2 places, 437 map road segments and zero road/tree-root overlaps among 3300 residents.
These durations include review orchestration; they are not production load benchmarks.
Evidence: `evidence/two_settlements/`.

World quality remains a draft. Inspected overview and street captures show the
low-rise settlement integrated with forest and individually fitted lots, but repeated
facades, regular street geometry and exposed banks still need design work. Only the
northern sidewalk traversal is checked; all market entrances, vehicle access and
common spaces remain unverified. A street screenshot showed 33 FPS; sustained 60 FPS
and laptop thermal headroom are not established. No performance acceptance is claimed.

Next required world work: move the combined bake out of the review harness into a
reusable production generator entry point; connect the remaining regional locations,
accepted static lakes and POI-owned underground; improve settlement variety and
landscape transitions. The broader legacy water persistence failures remain open.

## Vegetation roots after shallow grading — 2026-10-20

Native surface query 17 previously accepted support within +/-0.35 m of the
original generator height but returned that original height and slope. Shallow
road cuts could therefore leave accepted grass hovering. It now solves the local
edited lattice zero crossing and evaluates its slope. The existing bounded
support window remains: deeper excavation rejects roots instead of regrowing
plants in a pit. Sampling uses the same quantization as meshing, preserving exact
neighbor transforms when an edit merely allocates their shared terrain page.

Both native DLL variants rebuilt. Shallow-cut support, deeper mining, snapshot
restore, asphalt rejection, exact untouched tree transform/transition preservation,
terrain native and ground-cover streaming tests pass. Fresh graphical reopen of
the two-settlement save passes; road capture inspected. Evidence in
`evidence/vegetation_edited_roots/` includes the rejected intermediate neighbor
regression and initial test revision error. No save format or vegetation IDs change.

Scope: bounded placement-time native work, no added per-frame global scan. This
fix does not prove exact contact against every simplified rendered triangle, or
reproduce the user's exact camera location. The reported 15 FPS remains unexplained
and is not claimed resolved by this placement correction.

## First coastal inlet — 2026-10-20

`Play Coastal World.cmd` opens a new version-5 copy of
`coastal_settlements_20261020`, seed 42 / generator 18. Existing generator fields
and review saves are preserved; the usual neighborhood launcher still defaults
to version 4. The same world contains 20 buildings, the connecting forest road
and a new western beach location on the M map. First bake: 93.72 s.

Generator 18 adds one bounded western inlet (x < 72, z 968–1048), shallow shelf,
sand shading and a bare beach below 44.5 m. Inland terrain at the checked old
settlement/edge points is unchanged. The water is the existing NativeRegionalWater
store: fixed-unit bucket transactions, terrain clipping and compound saves.
The outer map edge has a sea-level meshing halo instead of an artificial air wall.
Its presentation configuration is derived from generator 18 before publication,
not a new serialized water format. Interior quantities remain authoritative.

Offshore is currently a two-triangle horizon outside the editable map, sharing
water lighting and world-space ripples, without scene-color/depth transmission
samples or cast shadows. An 8 m shallow-to-deep appearance blend meets that horizon.
This is a bounded coastal milestone, NOT dynamic ocean volume streaming or a
whole-world ocean LOD system. Offshore swimming/boats, distant edited ocean tiles,
all-side coast generation and moving near/far streaming remain unfinished.
Do not expand the existing 4096-region store limit to fill an entire ocean.

Targeted actual-world review passed: saved terrain + 3 places load, all 80 water
regions reuse cached terrain contacts with zero rebuilds, normal gameplay scoop
and return transfer exactly one unit, edited water snapshot restores, and native
ray intersection at x=0.01 meets the horizon at y=40 within 1 mm.
Cached water occupancy: 2,615,664 bytes; query mesh cache: 3,308,928 bytes;
no active simulation cells. Inspected near and overview images after removing the
initial beach vegetation and correcting the visible edge seam. Shoreline silhouette
variety and exposed headland ends remain draft quality.

1080p capped-60 short fixed-view horizon on/off sample (90 frames each): GPU median
5.623 ms hidden / 5.556 ms visible; p95 6.629 / 6.460 ms. The negative difference is
noise/warm-up, not a speedup or zero-cost proof. This measures only horizon toggle,
not total water cost, long-run thermals or an older laptop. Functional checks plus
the short images do not establish complete world-quality acceptance.
Evidence: `evidence/coastal_inlet/`.

## Coast direction and beach vegetation correction - 2026-10-20

The user requires ocean and beaches enabled by default for newly generated worlds,
with a disable option; existing saves retain their generation settings. This policy
is recorded in WORLD_BUILDING_STANDARD.md. The browser toggle and surrounding
coast are NOT implemented. The first inlet does not satisfy all-edge continuity.
Offshore travel is separately optional and remains unsupported: both movement and
native pose validation constrain walking positions to [2,1998].

Removed the blanket bare-beach root rejection from generator 18. Dry-beach roots
now have a deterministic grouped transition between 40.15 and 44.5 m. Wet roots
remain rejected. Terrain heights and saved authoritative state are unchanged.
Both native variants rebuilt with the pinned SDK. The native coastal check passes
(inland height preservation, deterministic dry roots/openings, wet-root rejection,
snapshot roundtrip). Initial test fixture exceeded the 64-point surface-query
limit; corrected to 60 points. Actual saved-world graphical check passed in 15.62 s,
including full-unit bucket return and water snapshot restoration. Near and overview
captures inspected: dry-beach vegetation is visible again. Evidence:
`evidence/coastal_vegetation_restore/`.

Overall coast quality remains unfinished: the overview still exposes artificial
ends of the limited inlet. The all-edge solution needs bounded detailed-water
residency and persistent edits with a continuous far representation. Filling the
whole boundary into the current 4096-region resident store is not an acceptable
implementation. No whole-ocean, offshore gameplay or sustained-performance claim.

## Continuous coastal terrain prerequisite - 2026-10-21

Native generator 19 adds a continuous coastal band to all four edges and corners.
The coast uses shared world-space noise, a rounded corner distance and a smooth
join to the original interior at 240 m. Sea datum remains 40 m. Sand and gradual
root placement now support this profile. Generator IDs 1-18 retain their fields;
no existing save is migrated. Profile 19 is deliberately not in the creation UI
until its water residency and interaction paths are implemented.

A targeted native test exposed an ordering error in the first implementation:
coastal heights changed derived lake levels and lake basins interrupted the dry
coastal rim. Fixed by preparing inland site/lake/underground parameters with the
original generator-17 field, then applying the coast after the complete inland
height calculation. Tests across seeds 0, 42, 1703 and 2147483647 pass: all perimeter
samples including corners are submerged, a continuous dry inner rim encloses the
land, inland samples outside 240 m are unchanged, the inner join is continuous,
and exact snapshot roundtrip retains profile identity. Legacy coast and native
terrain regression checks pass. Both DLL variants rebuilt with the pinned SDK.
Evidence: `evidence/surrounding_coast_field/`, including the rejected first field.

This is engineering evidence for the land field only, not in-world visual or ocean
acceptance. Remaining required work: bounded native ocean detail residency, durable
edited-region retention, a far representation joined to published detail, actual
four-side/corner visual and bucket/travel checks, default-on opt-out generation
settings and integrated fresh-save/reopen. Offshore travel remains separate and
unsupported. The existing 4096-region water store must not be expanded into an eager
whole-ocean allocation. Keep working on these dependencies before promoting the
coastal generator or moving to an unrelated feature.

## Native ocean residency prerequisite - 2026-10-21

Added bounded `NativeRegionalWater.update_ocean_residency(center,budget)` admission
and retirement using the existing half-metre cells, terrain occupancy patches and
surface publication path. The call admits/retires at most 32 regions, prioritizes
nearby regions and retains a wider hysteresis band. It is not called by the live
world yet: near/far publication must be integrated before showing streamed ocean.

Regions now distinguish ordinary water, pristine generated ocean, and ocean touched
by gameplay/terrain. Only pristine regions may retire. Initial occupancy acceptance
fills sea-level water once; invalidation makes it durable before asynchronous
replacement. Material mutation also makes it durable. Snapshot version 10 retains
ownership, including worker-frozen snapshots; ordinary lake saves still emit their
existing version 8/9 layout. The reader continues accepting older versions. No
flow/spillage or new mesher was added; the 4096-region limit was not increased.

Targeted native test passes initial occupancy/fill, material removal, exact edited
quantity and ownership through worker snapshot/restore, terrain invalidation,
retirement of pristine detail, and retention of edited detail after restore.
An 80-stop admission/retirement sweep peaks at 480 regions. That sweep does NOT
sample terrain or render every admitted region and is not a travel FPS benchmark.
Existing bucket/single-runtime checks pass. Actual saved inlet gameplay check at
1080p/cap60 passes in 16.81 s; near image inspected. Evidence: `evidence/ocean_residency/`.

Remaining: connect async worker cancellation/admission to the live world; publish
complete local detail with an ocean halo and far-surface mask (never expose partial
fill or reset edits); unload edited regions into durable cache instead of keeping
all touched regions resident; ensure map representation describes the implicit sea,
not just resident detail; actual all-side/corner bucket/travel and save/reopen
checks; default-on opt-out world creation. Current `water_ml` counts resident
explicit quantities, not total implicit ocean volume. Offshore travel remains
unsupported. These dependencies remain part of this work; do not promote the new
generator or treat this test as a playable surrounding ocean.

## Surrounding ocean integrated publication - 2026-10-21

Generator 19 now connects the existing lake runtime to bounded native ocean
residency. Eight presentation quads surround the map: the inner ring uses normal
water transmission and the outer horizon uses the existing cheap opaque variant.
World-space ripples and lighting are shared. The sea is static; no new simulation
or independent local water mesher was introduced. Existing generator 18 keeps its
inlet behavior. The new profile remains absent from the creation UI for now.

Native publication tracks completed regions, including empty owners. A 500x500
R8 coverage mask switches presentation only after the entire vertical column plus
its neighbor halo is published. Picking uses that same publication condition.
An initial visible rectangular boundary failed image review; retaining a full
published halo outside the visible switch removed it in inspected captures.
Missing procedural sea halo samples continue at sea level. Edited cells remain
authoritative. Retired scene meshes are freed rather than accumulated as empty
nodes. Unchanged mask images are not reuploaded. The native store pins a two-column
neighborhood of edits until durable edited-region caching is available.

Actual 1080p/cap60 world check passes: coastal surface ray matches y=40, normal
player bucket scoops/returns exactly one cubic metre, and the edited water snapshot
restores exact quantity and durable ownership. Optional travel check now covers
west, east, north, south, northwest corner and return to the edited west. It waits
for the full 11x11 visible footprint, not only its already-pinned center. An earlier
4 ms return number was misleading because it checked only that center; it is NOT
cache/load evidence. Corrected return takes 11.8 seconds. Fresh destinations take
about 12-15 seconds; initial preparation about 20 seconds. These delays are not
acceptable travel performance. The full targeted run took 99.13 s. Resident regions
stayed 676-776; scene mesh count also retired. Tests use teleport destinations,
not continuous swimming, fast vehicles, long-run or old-laptop benchmarks.
Native residency and legacy bucket/single-runtime checks still pass. Inspected
west/east/north/south/corner captures; no rectangular seam in reviewed final views.
Evidence: `evidence/surrounding_ocean_integration/`.

Remaining required work: cached/baked ocean occupancy and fast loading; durable
nonresident edited data rather than pinned regions; full-world save/reopen with
coastal settings; map representation of the implicit ocean; default-on opt-out
creation controls; continuous travel/underwater and repeated-edit validation.
Far water is presentation until local detail is ready, and offshore gameplay is
still unsupported. Do not claim complete gameplay or performance acceptance from
these functional tests or the capped FPS in screenshots. The main outstanding
work is still this ocean integration, not an unrelated feature.

## Bounded pristine ocean occupancy cache - 2026-10-21

Untouched terrain-only ocean regions now retire into a native LRU cache capped at
32 MiB / 1024 entries, with combined live+cached record admission bounded by the
existing region limit. Structure-bearing regions are not cached, avoiding a second
unaccounted structure-contact budget. Cache entries retain exact amounts, vacancies
and terrain contacts. Restoring a cached region bypasses sampling and republishes
through the usual mesh batch. Terrain/building invalidation against a cached region
first restores its prior amount and then makes it authoritative before invalidation.
Edits are never evicted as pristine cache entries. Restore clears the old cache.
This is an in-memory derived cache, not the outstanding durable edited-region cache
or an offline world bake; pristine cache entries may be regenerated after eviction.

Native checks pass exact no-resampling restore, distant invalidation, worker
snapshot ownership, and pressure eviction with 1200 valid pristine region records.
The pressure check verifies both entry and byte ceilings. Existing bucket check
passes. The first graphical cache-only run reused 576 regions but still took
10.876 s to return. This exposed repeated publication of small admission batches.
The runtime now defers publication while admitting the next coastal footprint,
without blocking bucket/development edits. Corrected 1080p/cap60 check: initial
coastal preparation 11.470 s, fresh opposite edge 11.778 s, cached full-footprint
return 5.318 s with 576 cache hits (roughly 10.8 MB cached). Total run 38.80 s.
Normal bucket scoop/return and snapshot checks pass; inspected return image has
no rectangular detail seam. Evidence: `evidence/ocean_occupancy_cache/`.

This is a measured improvement, NOT acceptable seamless travel performance. Fresh
sampling is still serialized one region per main-thread handoff; cached return
still rebuilds/publishes geometry. Remaining work stays active: bounded worker
batching or reusable mesh/cache publication, persistent edited-region storage,
baked cold loading, map coverage, creation options and complete save/reopen.
No default-on creation control or offshore gameplay is claimed implemented.


## Bounded ocean occupancy worker batches - 2026-10-21

Pristine ocean admission now hands up to eight occupancy patches to the existing
terrain worker per main-thread dispatch. Each worker invocation still samples only
one bounded patch slice; status-zero work returns to the existing cooperative queue.
Revision/cancellation and scene structure revisions still invalidate stale results.
Ordinary lake/bucket edits and cached building-only occupancy keep their existing
single-patch paths. This changes scheduling, not water geometry or representation.

Native regression compares batch and serial snapshots byte-for-byte and checks
revision/epoch rejection and the request cap. The existing bucket regression passes.
Actual-world 1920x1080/cap60 west/east/return test passes normal bucket transfer,
snapshot restoration, full-footprint publication, cache reuse and resident bounds.
Initial coastal readiness: 6.019 s (previous 11.470 s); fresh east: 6.433 s
(previous 11.778 s); cached return: 5.375 s (previous 5.318 s), 576 cache hits.
Total test: 34.71 s. Inspected both destination captures without a new rectangular
seam. Evidence: `evidence/ocean_worker_batch/`. These are one-run measurements,
not sustained frame-time or thermal proof, and still NOT seamless loading acceptance.

The comparable cold and warm delays now point toward geometry rebuilding/publication
and admission as the next measurement target, rather than increasing sampling batch
sizes. Reusable mesh publication, durable nonresident edited regions, baked cold
loading, implicit-ocean map coverage, default-on opt-out world creation controls,
and complete world save/reopen remain unfinished. Existing saves are unchanged;
outside-world gameplay remains unsupported and must stay separately optional.


## Terrain-fitted world creation with optional coast - 2026-10-21

Worlds now defaults to the terrain-fitted regional recipe (preset 10019), with a
checked Surrounding ocean and beaches option. Enabled selects immutable terrain
profile 19; disabled selects 17 with the same two-settlement recipe. Saved-world
launches never apply these creation settings. Earlier five-site preset 10012 stays
available with its existing preparation recipe. No saved world was migrated.

Moved the existing terrain-lot/central-market review generation into the shared
production `tools/prepare_terrain_world.gd`; its review test now uses that same
implementation. It accepts the selected seed, prepares 12 northern buildings and
8 central-market buildings, their terrain-fitted streets and connecting road,
bakes cartography, performs the ordinary compound save, and compares exact block,
model/furnishing/paving and navigation signatures in a separate read-only process.
The launcher publishes only after both phases succeed. Failure/cancellation and
existing-save preservation remain enforced. The native navigation archive now
accepts profile 19 as well as 17/18, with storage roundtrip coverage.

Both full creation paths passed using browser-default seed 1703 at 1920x1080/cap60:
coast_creation_check_20261021 and inland_creation_check_20261021. Each has 20
buildings, 364 terrain preparation edits, two public locations and 443 sampled road
segments in its map metadata. Coast creation took 80.98 s and reopen 18.89 s.
The route check found zero trees overlapping the sampled road corridor. The
published coastal world then passed a separate 21.74 s actual-world ocean bucket
scoop/return and native snapshot check; initial local coast readiness took 5.4 s,
so the known loading delay is not resolved. The final bucket check was read-only;
it does not establish durable player ocean edits across process restarts.
Browser policy/layout and native navigation tests pass; Python preparation suite
passes 16 tests, including both coast choices and failure-before-publication.
Inspected browser, neighborhood overview, central street and coastal images.
Evidence: `evidence/coastal_world_creation/`.

Known gaps remain explicit: the newer recipe has not yet received all authored
mines/cellars, inland lake fills, meadow paths, parked vehicles and residents from
the older five-site recipe. Do not confuse the available coast choice with complete
world-content coverage. Building variety, exterior landscaping and broad world
quality are still drafts; one-seed creation does not qualify every seed or prove
sustained performance. Next coastal dependencies remain fast detail loading,
durable nonresident edited-region storage, full implicit ocean map coverage and
save/reopen of actual coastal edits. Outside-border gameplay is still unsupported
and must remain independently optional when implemented.


## Whole-coast map coverage and preparation - 2026-10-22

The M map now surveys the complete profile-19 ocean perimeter without allocating
water regions. A bounded native procedural source offers 68,544 map subsamples;
edited top-layer regions suppress the implicit sea and contribute their actual
stored surface instead. Lower pristine water beneath an edited top layer remains
represented. Terrain visibility still handles excavation and roofs. The fast
pristine-sea path uses the shared inclusive terrain page stride; an added-roof
regression caught and corrected an initially wrong stride before publication.

Visibility jobs accept up to 256 samples, but retain at most 16 full density scans
per slice; responses may be prefixes, with explicit raster prefix validation.
Unedited ocean samples use the generator shortcut. Ordinary 16-sample callers and
the strict raster accept API remain supported. Water cartographic revisions now
exclude pristine admission, sampling, retirement and cache restoration, while real
edits invalidate continuations. Raw quantity surveys retain their separate full
resident-data revision. Map cache namespace v2 avoids incompatible old rasters.

Native tests cover all sides/corners, zero water allocation, bounded sample batches,
stale edits, stable streaming revisions, removed top-water suppression, retained
lower water, bulk-vs-density visibility and terrain roof/removal. Legacy saved-lake
survey, exact amount accounting, restoration, visibility and raster checks pass.
Corrected a test-only double-submit predicate in the legacy visibility harness;
the request had succeeded but its second invocation incorrectly reported failure.

Actual-world 1080p/cap60 map: first cold water layer 17.211 s, fresh-process cached
layer 1.644 s with zero visibility queries; both use zero resident water regions.
Streaming admission did not rebuild the completed layer. Inspected the whole-world
map: ocean surrounds all edges, with the two settlements and connecting road intact.
The production preparation reopen phase now waits for terrain/water/block/model
map completion and successful cache write/read before publication. Its saved-world
check passed in 39.72 s with a water cache hit and no visibility scan. This validates
the new preparation gate against the existing staged world; it is not a second
complete terrain/building generation run. Evidence: `evidence/ocean_map/`.

Cold map work remains expensive after relevant edits/cache eviction and cached
opening still scans procedural source points. Incremental map updates or a stable
native procedural identity can improve that without weakening edit correctness.
Coastal detail loading, durable nonresident edited water, full player-edit process
save/reopen, older authored-content integration and optional offshore gameplay
remain open. This change establishes regional map coverage, not world completion
or sustained laptop performance acceptance.


## Ocean player-edit persistence — 2026-10-22

The previously open basic fresh-process ocean-edit save/reopen check now passes.
`tools/check_ocean_persistence.py` clones the prepared coastal world to a unique
`ocean_persist_*` slot, never overwrites its source, and runs two sequential
1080p fullscreen/cap60 game processes. The first uses normal gameplay mouse input
to scoop exactly 1 m³, verifies local occupancy changed, saves the compound world
and completes durable shutdown. The second opens that slot and verifies the full
bucket, edited-region ownership and all 48 surrounding depth samples after coastal
residency has republished. Durable shutdown succeeds again. Evidence is in
`evidence/ocean_edit_reopen/`; runs took 16.28 s and 7.84 s respectively. These are
whole harness durations, not frame-time or loading benchmarks.

This is persistent gameplay evidence, not merely a native snapshot roundtrip. It
covers one coastal scoop and inventory conservation across restart; it does not
establish exhaustive bucket, terrain/building replacement, save-failure or large
edited-coast coverage. No runtime fix was required for this case. Durable eviction
of edited water remains unimplemented, coastal loading remains slow, and authored
world-content coverage and outside-border gameplay remain open. The reproducible
check defaults to the existing prepared coastal fixture and accepts --source for
another compatible prepared coastal slot.


## Edited-coast capacity failure — 2026-10-22

A short native residency-policy probe now reproduces the previously unmeasured
edited-water scaling limit. `tests/ocean_edited_scaling.gd` intentionally exits 1
while the requirement fails; this is not a passing regression or accepted baseline.
It admits near-coast regions, invalidates one tiny AABB per separated site through
the production API, then moves focus inland and drains bounded retirement calls.
The invalidation halo touches eight regions per site; each site pins 144 regions
including pristine neighbors. At site 26, admission hits the 4096-region limit;
3744 remain after retirement, occupying 34,265,088 native cell bytes. The pristine
control performs all 80 stops and returns to zero resident regions without a
capacity failure. Evidence: `evidence/ocean_edited_scaling/`.

This is a storage-policy test, intentionally without terrain sampling, contacts,
meshing or rendering. It does not establish real-game memory usage or FPS, nor
claim that 26 bucket clicks reproduce it (terrain invalidation has a larger halo).
It isolates retained edited ownership as the cause rather than terrain-generation
or GPU cost. The 1200-region post-travel diagnostic budget also fails at site 9;
capacity exhaustion is independent of that chosen diagnostic budget.

Required next implementation: durable edited-water region paging, integrated with
compound world-save checkpoints. Raising MAX_REGIONS, evicting edits into the
pristine cache, or keeping an unbounded second map in RAM are not fixes. Follow
`OCEAN_EDITED_STORAGE.md` for the exact consistency and acceptance requirements.


## Native water region transfers — 2026-10-22

Implemented the first required paging primitive in NativeRegionalWater:
`capture_region_snapshot` exports one edited ocean region using the existing strict
v10 water codec; `restore_region_snapshot` installs an absent region only after
coordinate, size/count, empty catalog, quantity, ownership and revision validation.
The importer refuses occupied/cached keys and active publication/fill, validates
before mutation, preserves quantities and vacancies, and queues a reconstruction
halo. The caller explicitly chooses whether cached occupancy has a matching terrain
identity; otherwise it queues resampling without changing authoritative quantities.
Empty edited regions remain real records, never absence/regeneration.

Native checks pass for actual sampled-and-edited sea, exact packet and quantity
roundtrip, duplicate/stale/wrong-coordinate/truncated/inconsistent-quantity rejection,
unchanged live state on failure, vacancy preservation and empty overrides. Existing
ocean residency and full-coast map checks also pass. Debug and release extensions
were rebuilt with pinned Zig and prebuilt godot-cpp (no SDK recompilation).
Evidence: `evidence/water_region_transfer/`.

This is a native prerequisite, not completed paging: no live eviction is enabled
and the edited-coast scaling failure remains. Durable blob/checkpoint storage,
compound-save integration, bounded asynchronous transfer coordination, unloaded
map and far-view representation remain required before safely enabling retirement.


## Durable water blob/checkpoint store — 2026-10-22

Implemented NativeWaterRegionStore as a serialized native I/O owner. It validates
edited-region packets, writes immutable SHA-256-addressed blobs, and publishes an
immutable sorted coordinate/digest checkpoint only after validating its referenced
blobs. Windows writes flush, read back for verification, then rename without
replacement. An exclusive directory handle prevents competing writers. No mutable
current-world pointer is stored here: selecting a water checkpoint must belong to
the compound world archive, preserving older saves when newer unsaved blobs exist.

Tests pass for publishing original and empty-override versions, reopening the store,
reading both checkpoints byte-exactly, exclusive-writer rejection, malformed and
mismatched region rejection, duplicate catalog rejection, missing checkpoint and
corrupt blob failure, refusal to overwrite corrupted content-addressed identity,
and continued readability of the prior checkpoint after newer data fails. Native
region-transfer and ocean-map regressions also pass. Both water DLL targets rebuilt
against prebuilt godot-cpp. Evidence: `evidence/water_region_store/`.

This is not runtime paging yet. No live world eviction or new save format is enabled.
The store is synchronous and must run on the planned I/O worker, never gameplay's
main thread. It bounds packets to 8 MiB and checkpoint metadata to 65,536 entries;
currently each checkpoint publication validates all references and each read parses
the selected manifest. Runtime integration needs bounded/incremental coordination
and retained manifest indexing. Checkpoint reference retention and garbage collection
are not implemented, so unreachable blobs currently remain on disk. Compound-save
integration, stale transfer guards, map/far presentation of unloaded edits and the
edited-coast scaling gate remain open and required.


## Bounded native water I/O worker — 2026-10-22

Added NativeWaterRegionIO around the immutable region store. One native worker
per coordinator accepts bounded writes and checkpoint reads, returns ticket/epoch/
coordinate-tagged acknowledgements, and retains reservations until results are
consumed. Read jobs reserve the maximum 8 MiB packet; configuration caps outstanding
requests at 32 and payload reservations at 64 MiB. Reservations cover queued/result
payloads, not total decoder/OS process memory. Stale epochs clear pending/completed
work and discard active completions; an already executing immutable write may leave
an unreachable blob but cannot change any selected checkpoint. Close joins the
worker and clears reservations. No scene or live-water pointers cross threads.

Native test passes for durable asynchronous write/read, exact packet restoration,
backpressure including unconsumed completions, cancellation, old-epoch rejection,
new-epoch success, explicit missing-checkpoint failure, reservation high-water bound
and joined shutdown. Evidence: `evidence/water_region_io/native.log`. Debug/release
DLLs rebuilt with prebuilt godot-cpp. No runtime eviction is enabled yet.

Save-path inspection confirms `terrain_backend._apply_components` already resolves
`serialize_snapshot` on its ordered worker, while `NativeRegionWorldArchive` wraps
compound publication for block/model stores. Water checkpoint selection must join
that compound archive transaction; it must not be stored as a separate mutable
current pointer. Remaining work: checkpoint metadata/index and retention, provider/
archive integration with legacy snapshot migration, acknowledgement-guarded region
eviction and restoration, unloaded map/far surfaces, and the failing edited-coast
scaling/actual-world travel gates. This worker is a prerequisite, not a claim that
those gates now pass.


## Bounded water checkpoint index — 2026-10-22

Region reads now retain one verified packed checkpoint manifest and binary-search
its sorted keys, instead of reading/parsing the full manifest for every region.
The retained index is bounded to 2,621,484 bytes including its identity (65,536
entries); switching checkpoint replaces it and closing releases it. Blob reads
still verify SHA-256 and region payload validation on every read. Once verified,
immutable checkpoint metadata stays trusted for the lifetime of its cached index;
external manifest modification is detected on reloading the index, not on each hit.

Added checkpoint_page with at most 256 coordinate/digest entries per call and strict
cursor bounds, for future bounded streaming/map admission. Tests verify exact
membership, repeated-read reuse without additional index loads, cursor/size limits,
index bound, corrupt-blob rejection despite cached membership, and existing worker
behavior. Evidence: `evidence/water_checkpoint_index/`. Both native DLL targets
rebuilt. Initial index loading still validates the complete bounded manifest on the
I/O owner; this is not a main-thread runtime API. Checkpoint publication still
validates all references. Live world checkpoint/provider integration, retention/GC,
eviction, unloaded edited-water rendering and scaling gates remain unfinished.


## Worker checkpoint publication and compound archive proof — 2026-10-22

NativeWaterRegionIO now accepts immutable packed coordinate/digest submissions for
checkpoint publication on its existing bounded worker. Checkpoint jobs share queue
limits and cancellation with region transfers, reserve submission bytes plus 8 MiB
for validation work, and return a ticket/epoch-tagged checkpoint acknowledgement.
Caller packed-array mutation after submission cannot modify the job. Reservation
accounting is a payload/work allowance, not a total-process memory cap.

`water_checkpoint_archive.gd` passes using the actual NativeWorldArchive codec and
durable publisher with synthetic terrain/inventory sections and real water packets.
It verifies region acknowledgement before checkpoint publication, queue backpressure,
immutable submissions, old canonical preservation while newer blobs exist, missing
blob rejection leaving the canonical unchanged, and canonical/backup selection of
matching old/new water and inventory markers. Existing region-I/O tests pass.
Evidence: `evidence/water_checkpoint_archive/`. Both DLL targets rebuilt.

This proves the native transaction composition, not gameplay provider integration:
synthetic terrain/inventory markers are not full gameplay snapshots. The actual
lake provider still saves its monolithic v10 snapshot and cannot evict edits. Next
required integration remains a checkpoint-bearing water component format with
legacy migration, archive/provider and clone-tool support, safe acknowledged
unloading, unloaded map/far representation, retention/GC and actual-world travel
and save/reopen checks. The edited-coast capacity regression remains failing.


## Checkpoint-bearing water component adapter — 2026-10-22

NativeWaterRegionStore now publishes a TFWS v1 component: a 48-byte header holds
its immutable checkpoint identity and the length of an embedded water snapshot.
Edited ocean records are published to that checkpoint; ordinary/pristine records
and the lake catalog remain embedded. Source partitioning is native and preserves
all exact quantities, vacancies and contacts. No save selects this component until
all referenced blobs and checkpoint publication succeed. Expansion verifies the
checkpoint and packets, rejects resident/archive ownership overlaps, and rebuilds
the original validated snapshot; ordinary legacy snapshots and catalogs remain
readable. Both methods operate on private copies, not live gameplay stores.

Tests pass for exact original/empty versions across reopen, malformed lengths,
missing checkpoint failure, overlap rejection, ordinary legacy passthrough and
actual terrain-sampled/edited ocean byte-exact restoration (not just synthetic flat
records). Evidence: `evidence/water_storage_snapshot/`. Debug/release DLLs rebuilt.

The adapter is not enabled in the gameplay provider yet. Its eager expansion is a
compatibility bridge bounded by the existing 4096 resident region limit, not the
final large-world load algorithm. Publication and expansion belong on a worker;
load must subsequently become metadata-first before enabling live eviction. The
component header relies on the enclosing world archive checksum for integrity.
Required next work: hook component codec/validator/preparer and storage path into
world persistence, copy .water dependencies in clone/backup tools, durable-reference
retention/GC, metadata-first loading, guarded retirement, unloaded map/far visuals,
and the edited-coast capacity plus actual-world travel/save gates.


## Gameplay checkpoint-backed save/load enabled — 2026-10-22

Connected the native TFWS adapter to both terrain backend compound-save paths
(frozen publication worker and ordered synchronous shutdown save), before outer
archive publication. Loads expand checkpoint components on the loading worker
before existing addon validation/preparation. Missing/invalid sidecars fail loading
with writes disabled; failed checkpoint conversion prevents canonical publication.
Legacy non-checkpoint loads remain unchanged. Actual edits use the existing native
runtime and bucket path; this changes persistence only, not water behavior.

The .trw.water sidecar now follows clone_world's staged dependency copying before
canonical publication. Four clone-cache/dependency tests pass, including preserving
an existing destination's edited water. An isolated prepared-world copy passes the
actual 1080p/cap60 gameplay scoop/save/restart test: exact 1 m³ bucket quantity,
48 local depth samples and edited ownership restore, and the canonical component
is explicitly asserted to contain TFWS. Whole harness times: save 19.06 s, reopen
8.29 s. Cloning that checkpoint-backed save and reopening it also passes in 7.99 s.
Evidence: `evidence/water_checkpoint_gameplay/`. Source player worlds were untouched.

This closes real provider/save-path integration and dependency cloning. Eager load
still expands all water into the existing resident store; therefore capacity
exhaustion is NOT fixed and live eviction remains disabled. Next: metadata-first
restore, resident/unloaded ownership and acknowledgements, far/map representation,
reference-aware garbage collection, failure injection at the gameplay load/save
boundary, and the previously failing edited-coast scaling plus travel regression.
New checkpoint-backed saves require this updated build and their .water directory;
backups must preserve that directory alongside .trw/.bak and other dependencies.


## Production water persistence failure guards — 2026-10-22

Added a short headless failure-injection check invoking the actual terrain backend
_load, _save and _publish_frozen paths against an isolated compound archive with
real native terrain and checkpoint water. An exclusive sidecar lease, corrupt blob
and missing checkpoint each prevent loading and disable writes; attempting save
after failed load preserves canonical bytes. Repairing the dependency restores
successful loading. Injected save-time sidecar lock failure reports unsuccessful
frozen publication and leaves the canonical archive unchanged. This validates the
production backend boundary, without claiming OS power-loss testing or a graphical
error-screen review. Evidence: `evidence/water_storage_failure/`.

Also corrected the checkpoint writer to preserve valid legacy lake-catalog payloads
already accepted by the reader/validator. Invalid payloads still fail. Legacy
catalog read/write and snapshot roundtrips pass after debug/release DLL rebuild.
Live edited-water eviction and metadata-first restoration remain the next required
capacity fix; these failure checks do not change current resident-region limits.


## Selective archived-water metadata admission — 2026-10-22

Added native describe_water_snapshot and checkpoint_window APIs. Description
validates the TFWS/base/checkpoint metadata and disjoint base/archive ownership,
returns the embedded base and explicit deferred checkpoint identity, and explicitly
reports blobs_verified=false. It does not silently equate metadata membership with
verified blob availability. Window queries binary-seek the x range, inspect at most
1024 records and return at most 256 coordinate/digest references per invocation;
continuations are indices into the immutable checkpoint. Blob read validation is
unchanged and unavailable blobs still fail rather than becoming empty water.

A 6000-entry synthetic manifest (deliberately without blobs) proves metadata can be
queried beyond the 4096 resident-region capacity without allocating those regions.
The exact selected window has 606 entries; 3000 records are inspected across bounded
calls and no duplicates occur. Real single-region checkpoint metadata also passes.
Synthetic metadata is not evidence of 6000 durable water edits or render performance.
Existing snapshot compatibility and production failure-guard checks pass. Evidence:
`evidence/water_metadata_window/`; debug/release native DLLs rebuilt.

Gameplay still eagerly expands checkpoint water. Required next step is native live
resident/deferred ownership and acknowledgement guards, then load-provider switching,
streamed blob admission, map/far-view handling and save capture of deferred references.
The metadata API alone must not be enabled as a partial load that omits unknown edits.
Live eviction, capacity exhaustion, reference retention/GC and travel verification
remain unfinished.


## Save merge preserves deferred edited-water references — 2026-10-22

Added native merge_water_snapshot(resident, inherited_checkpoint). It starts from
an immutable inherited manifest, replaces only resident edited-region entries,
retains unloaded references including explicit empty overrides, and publishes a new
checkpoint without mutating the inherited one. Pristine/ordinary resident overlap
with inherited edited ownership is rejected. Missing inherited metadata or blobs
aborts publication. No inherited region is reconstructed into the resident water
store during merge, though publication still validates referenced blobs sequentially
on the worker. Existing publish_water_snapshot now uses this same merge path with
no inherited checkpoint.

Tests pass for distant reference preservation, a new local edit, exact empty-region
replacement, no duplication, no-resident-edit save identity, old-checkpoint
preservation, overlap/missing-checkpoint failure and exact totals after compatibility
expansion/reopen. Production failure guards and the actual 1080p/cap60 gameplay
scoop/save/restart also pass (whole runs 16.95 s / 8.14 s). Evidence:
`evidence/water_deferred_save/`; both native DLL targets rebuilt.

This supplies the save operation needed by future selective residency; live gameplay
still expands all archived edits and passes no inherited deferred index. Next required
work remains native resident/deferred ownership, acknowledgement-guarded retirement,
selective runtime admission, map/far visuals and reference-aware storage cleanup.
The edited-coast exhaustion test is still not resolved. Publication's full-reference
validation is also an explicit scaling cost to address without weakening integrity.


## Native deferred-water identity guards — 2026-10-22

NativeRegionalWater can now register bounded batches (256) of deferred region keys
and exact blob digests, up to 65,536 references, atomically rejecting resident/cache
overlap, duplicate input and identity conflicts. Repeated identical batches are
idempotent. Deferred keys block procedural ocean admission and generic region
allocation. Region restoration hashes the packet against its deferred identity
before mutation, then atomically replaces that reference with resident ownership.
A bounded metadata export exposes deferred references for the save merge path.
Whole-world restoration clears/swaps this state correctly. Legacy whole snapshots
and frozen captures fail closed while deferred references exist, preventing a
partial resident-only save from silently losing distant edits.

Tests verify exact procedural footprint exclusion (415 allocated rather than 416),
registration atomicity/conflicts, failed capture, wrong-blob rejection, exact single
admission, metadata export and deferred clearing during world replacement. Existing
residency and deferred-save checks pass. Evidence: `evidence/water_deferred_ownership/`.
Debug/release DLLs rebuilt. An initial test queried a nonexistent request status key;
that ineffective assertion was replaced with exact resident/pending counts before
recording final passing evidence.

This state is not installed by gameplay yet. No automatic eviction is enabled.
Before switching: add unavailable-overlap edit admission, guarded durable retirement,
selective provider restore/save handoff, map and far/near visuals for unloaded edits,
and actual-world travel/capacity checks. Existing query/depth paths do not yet expose
complete pending semantics for unloaded regions, so treating this primitive alone
as a playable selective loader would be incorrect. Capacity exhaustion remains open.


### Deferred water edit admission (2026-10-22)

Native water now exposes a spatial deferred-overlap check using ordered region
row lookups. Placement/refill, bucket targeting, removal brushes, bounds removal
and initial filling refuse operations crossing deferred data before changing
resident quantities. Terrain edit admission checks the same bounds with the
terrain invalidation halo. This adds no region sampling or loading on its own.

The targeted test mixes a resident region with its deferred neighbour and checks
that removal, brush, placement and filling cannot partly mutate the resident
water. Normal in-world scoop/save/reopen also passes (18.07 s / 8.72 s whole test
runs, not frame or loading benchmarks). Evidence: `evidence/water_deferred_edit_guard/`.
Both native DLL configurations rebuilt. These are correctness checks, not new
visual acceptance or a capacity fix.

Still required before selective gameplay loading: building mutation admission,
loading requests/retries, guarded durable retirement, provider save/load handoff,
map and distant visual handling, and actual edited travel/capacity proof. Live
unloading remains disabled; the documented edited-region capacity failure is open.


### Building admission over deferred water (2026-10-22)

Native block edits now check an admission callback after staging and before any
publication. LakeWorld connects it to deferred-water overlap in world coordinates.
The same gate covers undo/redo, authored resident-region replacement and combined
prefab commits. Ordinary loading of an identical saved building region remains a
paging operation rather than a new solid replacement.

Tests prove mixed block batches do not partly commit, blocked undo retains its
history, resident replacement leaves data unchanged, and edits resume after water
loads. The combined prefab regression verifies rejected placement refunds inventory
and preserves all attached models, then successfully places again. This test caught
and fixed a pending-transaction cleanup bug on admission rejection. Evidence:
`evidence/water_building_admission/`. Debug/release structures DLLs rebuilt.

Live water eviction remains disabled. The next required work is verified durable
retirement and selective runtime loading/save handoff, including map/far visual
preservation. The edited-coast capacity failure remains unresolved.
Integrated normal-world scoop/save/reopen also passes (18.62 s / 9.52 s harness runs; not performance acceptance).


### Verified edited-water retirement primitive (2026-10-22)

NativeWaterRegionStore now issues an immutable native receipt only after successful
verified publication/read. The receipt holds coordinate, exact packet and digest;
script-created empty receipts are invalid. The bounded I/O worker passes these
receipts back with its existing epoch/ticket result. NativeRegionalWater retirement
requires matching revision and byte-identical current region, refuses active mesh
publication/fill, then replaces resident ownership with the durable digest. It
releases cell/contact storage and schedules halo mesh retirement through the normal
publication path. It does not put edited regions in the pristine RAM cache.

The native regression exercises worker write/read, stale revision, changed-packet
rejection even with a current revision, exactly-once retirement, exact quantity
reload, empty overrides, and failed publication without a receipt. It also publishes
initial geometry and verifies retirement clears its picking cache. Existing I/O and
merged-checkpoint save tests pass. Ordinary in-world save/reopen passes (16.20 s /
7.85 s whole harness runs, not performance acceptance). Evidence:
`evidence/water_region_retirement/`. Both native configurations rebuilt.

This is not yet live gameplay eviction. Runtime must retain the owning store,
reject wrong-epoch completions, release consumed receipt buffers, preserve all
unloaded references in compound saves and account resident versus archived amounts.
The receipt proves a verified blob write/read, not compound-save publication or
protection against later external file deletion. Retention/GC must respect these
references. Selective loading, map/far visual preservation and the actual edited
travel/capacity acceptance remain required. No increase to resident capacity.


### Mixed resident/deferred water save handoff (2026-10-22)

Water storage capture now freezes deferred digest membership alongside resident
records. Worker serialization emits a bounded TFWT v1 transient handoff (24-byte
header, ordinary resident snapshot, sorted 40-byte key/digest records; at most
65536 references and 64 MiB total). Capture reservation includes metadata. The
production component validator checks this handoff, including disjoint ownership,
strict ordering, domain, sizes and header. Legacy direct capture still refuses to
silently omit deferred records. LakeWorld capture selects the complete handoff.

The save store verifies every referenced blob, merges resident edits and publishes
the existing TFWS checkpoint component. TFWT is explicitly rejected as a canonical
load format. The production backend test covers frozen capture after retirement,
a subsequent live edit, compound publication/reopen, byte-identical region contents,
and a corrupt unloaded blob preserving the previous canonical save. Existing
ownership/storage snapshot checks pass. Evidence: `evidence/water_streaming_save/`.
Both native configurations rebuilt.

Runtime eviction is still disabled. An active loader must share/coordinate the
sidecar owner with saving (the existing backend currently opens its own exclusive
store); selective loading, map/far representations, quantities and bounded retained
receipt memory still need integration. Eager reopen retains its existing capacity
limit. Passing this save test does not resolve the edited-coast scaling failure.
Normal in-world scoop/save/reopen also passes (16.66 s / 9.94 s harness runs; not performance acceptance).


## World-content milestone resumed — 2026-10-22

Following the user's request to move forward beyond water, stop expanding water
scope now. Keep accepted static bucket/lake gameplay and optional default-on coast.
Automatic edited-ocean eviction remains disabled; its capacity failure is explicitly
open in OCEAN_EDITED_STORAGE.md. Return before large-world readiness qualification,
or sooner if ordinary play reaches the cap or risks saved edits. Preserve tested
native retirement/save work; do not discard or call it finished.

Next deliverable: one connected cellar cottage in the default terrain-fitted central
settlement, with excavation in the master plan before building publication, a working
entrance/ladder/storage route, and fresh-process persistence. No ambient cave network.
Planning and placement checks alone do not establish human or visual acceptance.
After this, remaining regional locations/roads and coherent exploration remain the
priority; ocean micro-optimization must not silently resume as the main milestone.


### Default market cellar integrated — 2026-10-22

One of the eight central-market cottages now uses the existing cellar/ladder/chest
prefab. The terrain-lot planner distinguishes surface grade from underground prefab
origin, keeps the approach at surface grade, and appends underground excavation to
the master earthworks after surface/road grading and before any building placement.
No runtime generation processor, new water work, or ambient cave network was added.

Native combined checks pass: exactly one cellar, excavated interior, matching street
approach grade, supported foundations and intact connecting roads. Full default
coastal generation and fresh-process reopen pass in the separate save slot
`market_cellar_42_20261022` (seed42/gen19,20 buildings,2 public places,441 map road
segments). Existing saves were not modified. Actual player movement in that saved
world passes street approach, steps, opening the door, entering, ladder descent,
climbing back out and return to the street, in 44.18 s total test runtime. The test
uses temporary/read-only mode and discards door/player changes.

Images were inspected. Initial preparation captures had an inventory overlay;
future capture code closes it. The follow-up approach shows a supported cottage
entrance, while the underground capture confirms masonry walls but is close to the
ladder. These do not establish complete room art acceptance: the cellar remains
plain, storage interaction was not newly tested, and no human review or sustained
frame-time qualification is claimed. Existing furnished-region snapshot contents
match after reopen. Evidence: `evidence/market_cellar_world/`.

Next world-content work stays on coherent regional exploration and missing locations,
including the owned mine and other connected destinations. Retain the water return
criteria above; do not silently restart ocean optimization as the main milestone.

### Generated cellar chest interaction — 2026-10-22

Extended the actual saved-world player route to walk away from the ladder, open
its cellar chest through E, deposit three stone through the storage UI, withdraw
three, and compare both inventories exactly. The player walks around to the
ladder's climbing side, climbs out and returns to the street. This passes in the
existing generated market save at 1920x1080/cap60 in temporary read-only mode.
Evidence: `evidence/market_cellar_storage/` (console, harness result and room image).

Two failed test iterations are retained: granting fixture inventory after opening
storage correctly rejected a stale revision; refreshing the fixture UI resolves
that. A direct return waypoint intersected the ladder; the route now walks around
it. Neither required weakening runtime validation or changing gameplay code.

The room image was inspected: chest and masonry are visible, but the room remains
plain and the development HUD is visible. This is not human/art acceptance or a
performance qualification. The harness currently uses the development tool mode;
normal gameplay-mode parity and a fresh-process deposit/save/reopen on a disposable
world copy remain required before closing the storage milestone. No user save was
modified and no persistence claim is inferred from the inventory roundtrip.

### Generated cellar storage persistence closed — 2026-10-22

`tools/check_cellar_persistence.py` clones the generated market save, including
regional sidecars, into a new `cellar_persist_` slot. Both graphical processes use
1920x1080/cap60 and normal gameplay construction mode. The first walks from the
street through the door and ladder, opens the actual cellar chest with E, deposits
three fixture stone through its UI, and saves through normal compound publication.
The second opens that snapshot read-only, compares exact chest and player inventory
packets, repeats the route, and verifies the reached chest identity and native
removal protection. Both pass. Source canonical SHA-256 remained unchanged.
Evidence: `evidence/market_cellar_persistence/`.

The first reopen harness omitted --snapshot-readonly while using temporary mode,
which created a fresh world rather than loading the clone; that failed log is
retained. Correcting the harness establishes the persistence result without a
runtime change. An already-open saved door is used without toggling it closed.

This closes the previously listed cellar storage interaction/gameplay/persistence
check. It does not close the unrelated legacy shutdown-drain/ID-reuse regression,
room art/human acceptance, global storage scaling or sustained performance. Continue
connected regional destinations and the owned mine; keep those open requirements
visible rather than extending water work or polishing this room indefinitely.

## Bundled generation verification — 2026-10-23

The new engine-owned generator created, reopened/verified and published
exported_world_42_20261023 from an executable beside its exported PCK and libraries,
without a source-project path or runtime Python. See WORLD_WORKFLOW_REDESIGN.md and
evidence/native_world_generation/exported_generation_run.json. Clean-machine
release-template installation remains unverified. This closes the bundled runtime
creation dependency gap, not the larger native/compute/storage/vegetation rewrite.


2026-10-23 rewrite follow-through: generator layout options, native coastal preview,
lot-fitting CPU reduction, and seed0 road-exit correction are implemented. Details
and retained failures: WORLD_WORKFLOW_REDESIGN.md, "Generator options and route
correctness". Newly discovered missing generated lake initialization is being
integrated before broader world review. All previously open rewrite items remain
open until their stated evidence exists, including far tree shadows and vegetation
owner-publication continuity; irregular scattering alone does not close them.


2026-10-23 continuation: distant canopy shadow substitutes and explicit interrupted
publication recovery now have targeted/integrated evidence in WORLD_WORKFLOW_REDESIGN.md.
This supersedes their earlier wholly-unimplemented status. Native worker capture
scaling and sustained travel performance still need evidence; shadows remain an
approximation on terrain. Generated lakes now persist through fresh-process reopen,
but inland map preview and broader basin admission remain open. Next dependency:
vegetation streaming/publication continuity, preserving native interaction and stable
harvest IDs. Close it only with moving-view and edit/removal regression evidence.
All other listed full-rewrite requirements remain open.


2026-10-23 workflow continuation: selected-world photograph/settings display and
manual photo refresh are implemented; cold read-side model metadata writes were
found and corrected by moving cache baking to save publication. Integrated cold
capture and native bootstrap checks pass, but packaged end-to-end creation with
these changes is still running. Generation now exposes actual stage/counter progress.
Newly identified pipeline gap: offline creation reuses interactive publication for
hundreds of grading sections, repeatedly building intermediate terrain. Offline new-world grading now applies identical native packets before first mesh
admission; full archive equivalence and actual bake/reopen pass for seed1703.
Details, remaining bundled coverage and limits are in WORLD_WORKFLOW_REDESIGN.md. Do not close earlier large
edit/mining latency, compute, map/content or storage-capacity requirements from this.


2026-10-23 cache handoff: preparation and play now share the bounded terrain mesh
cache. Verified edited-map raster publication transfers the preparation key to the
playable world. Independent-worker mesh parity and actual saved-world map reuse
pass; see WORLD_WORKFLOW_REDESIGN.md. These close the identified handoff omissions,
not whole-scene loading time, compute generation, complete preview layers, storage
capacity or populated travel. Keep the earlier mining first-response failure open.


2026-10-23 preview coverage: inland lakes are now present alongside ocean, roads
and building footprints, using shared generated catalog fitting and bounded native
surface surveys. Two actual saved-world map comparisons pass within one regional
pixel; all layout preview caches pass cold/warm parity. The full-volume preview
candidate failed its15s gate and was removed. See WORLD_WORKFLOW_REDESIGN.md.
POI planning/preview, broader admission and the other full rewrite requirements
remain open. The surface preview does not alter static water gameplay.
