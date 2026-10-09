# TerraForest delivery plan and coverage register

Updated 2026-10-09. TerraForest is an integrated development world, not a completed game-ready world engine. The next objective is first-round coverage of the original scope, followed by combined scale and endurance qualification. A coherent playable area demonstrates integration; it does not replace missing systems or reduce the large-world goal.

This is the current delivery-order and coverage reference. [Delivery history](DELIVERY_STATUS.md) records evidence at the time of each change; older entries are not current status. [World systems design](WORLD_SYSTEMS_DESIGN.md) retains the broader architecture contract. A documentation update alone closes no implementation gate.

## What counts as first-round coverage

A system needs a usable main-world path, persistent state where appropriate, a small correctness check, a representative performance check, and explicit limits. An isolated addon, API test or visual showcase is supporting evidence, not integrated coverage. User-visible behavior also needs a human checkpoint. Production qualification additionally requires combined workloads, sustained operation and release checks.

Statuses below distinguish **integrated partial** (usable but coverage gates remain), **native partial** (infrastructure exists but gameplay integration remains), and **planned**. No row is certified complete by this register. Later networking implementation is a deliberate sequencing decision, not completion of the original multiplayer requirement.

## Original scope and remaining coverage

| Requirement | Current position | First-round completion gate |
| --- | --- | --- |
| New combined project and independently usable addons | Integrated partial: terrain, forest and companion addons; source projects preserved | Verify documented dependencies, addon isolation and supported Windows build/install paths; retain a full support matrix |
| Volumetric terrain, large caves and mountains | Integrated partial: editable terrain and seeded generation paths | Generate and traverse representative above/below-ground regions; mine nearby and after travel with visual and collision correctness, save and reload |
| Underground materials and veins | Integrated partial: seeded geology and excavation accounting | Demonstrate discoverable material variation, correct appearance/rewards and reproducibility after reload in the playable world |
| Volumetric water and lakes | Integrated partial: static connected occupancy, edit rebakes, saved definitions, basic swimming/underwater feedback and generator 4 lake placement | Qualify generated-lake readiness and combined rendering, add versioned bake reuse, and test shoreline/cave occupancy, editing and reload; explicitly retain static-basin limits |
| Asphalt roads | Integrated partial: native grading/paving and connected street authoring | Drive connected roads across loaded region boundaries, edit/save/reload them, and verify terrain, buildings and vegetation remain consistent |
| Block shapes, prefabs and static model objects | Integrated partial: cubes, slabs, stairs, slopes, posts, spheres, placement/transforms/history and persistence | Author a usable building with interior objects and access features; verify selection, collisions, undo where supported, and persistence through travel |
| Large buildings, towns and cities | Integrated partial: house/tower examples and native connected multi-street settlement authoring | Implement a reproducible settlement generation/authoring workflow with connected roads, supported buildings and usable interiors; measure representative detailed structures, not just empty shells |
| World generator and editor | Integrated partial: generation, terrain editing, construction and site preparation | One reproducible workflow creates, edits, revisits and reloads the combined world; rejected operations leave consistent state |
| Loading, baking and caching | Integrated partial for terrain/blocks; opt-in main-world model paging with lifecycle barriers | Automatic model region selection, safe save/checkpoint handover and lifetime handling; correct edit invalidation and warm reuse; demonstrate bounded residency and arrival behavior |
| Player, toolbelt, inventory and unified interaction | Integrated partial: movement, UI, pickups/resources and paid gameplay construction separate from free editor | Complete a coherent gather/build/use/save/reload loop across terrain, buildings and objects; verify input focus and unavailable-region behavior |
| Vegetation including stones, plants and grass | Integrated partial for trees and native selection/sparse updates | Add representative small stones, plants and grass with density/LOD tiers; individual stones, plants and grass clumps must support removal and placement, survive travel/save/reload, and follow gameplay inventory rules while editor placement stays free; verify local mining/building disturbance and combined rendering costs |
| Efficient world representation and storage | Integrated partial: versioned compound snapshots, regional structures, checksums/recovery and derived caches | Demonstrate bounded memory/disk behavior under edit, travel, save and reload; distinguish authoritative records from disposable caches; retain unresolved terrain addressing/delta/compaction requirements |
| High amounts of entities | Native partial: bounded stores, spatial queries and active kinematic iteration | Integrate representative rendered, interacting entities with activation/sleeping and representative animation/collision work; measure actual work at stated populations |
| Vehicles and high-speed travel | Integrated partial: one vehicle, native driving/suspension components, readiness handling and parked persistence | Exercise drive/park/reload and repeated travel through combined content; establish bounded activation for multiple vehicles and safe collision arrival behavior |
| Large multiplayer world | Planned implementation; some storage/identity prerequisites exist | During coverage work, audit authority/identity/command boundaries and record violations. Later gate: server plus two clients, edits, late join, loss/reorder, bounded interest/traffic and measured scaling |
| Professional visuals, resilience and headroom | Partial: materials/LOD, lifecycle checks and short graphical evidence | Inspect combined terrain, buildings, vegetation and water; fix visible defects; then qualify frame tails, resource growth and long sessions at documented workloads |
| 60 FPS at 1920 by 1080 fullscreen | Configuration and new-host baseline exist; sustained target unproven | Enforce full-resolution graphical measurements, report frame tails and failures, separate CPU/GPU/power results; qualify sustained target on stated hardware |
| Native hot paths, Zig and prebuilt godot-cpp | Integrated partial: pinned toolchain and multiple native addons; script adapters remain | Profile remaining hot paths and migrate substantial runtime work; preserve native ABI/build reproducibility and mod/UI support boundaries |
| Git publication, licensing and distribution | Git repository published; project code 0BSD with separate dependency/asset notices | Preserve provenance, test clean installation/export and addon distribution; declare supported platforms and actual limits |

Current implementation sources include [project guide](../README.md), [player runtime](../addons/player_runtime/README.md), [vehicle runtime](../addons/vehicle_runtime/README.md), [vegetation runtime](../addons/vegetation_runtime/README.md), [structures](../addons/structures/README.md), and [model bootstrap](MODEL_WORLD_BOOTSTRAP.md). Historical README limitations can lag later delivery entries; current code and scoped evidence determine implementation status.

## Delivery sequence

Only one delivery milestone is active. Supporting work must name the coverage row and completion gate it enables. Work already implemented is reused rather than restarted to fit this sequence.

| Milestone | Deliverable | Exit decision |
| --- | --- | --- |
| M1 Current integration closure — disposition recorded | Dependable human checkpoint and a concrete disposition for opt-in model streaming | Address checkpoint defects as found. Complete automatic model paging/save lifetime integration with targeted evidence, or explicitly retain the existing path and register its limitation and return trigger. Do not enable incomplete paging merely to claim integration |
| M2 World content coverage — active | Generation, water, roads, structures/static props, vegetation variety and settlement workflow in the same saved world | Close the applicable coverage gates above; report any remaining gap instead of silently moving it to qualification |
| M3 Gameplay and simulation coverage | Gather/build/use loop, representative active entities and multiple-vehicle activation | Actual rendered behavior, persistence and bounded simulation are demonstrated; an entity count in a native store is insufficient |
| M4 Combined area qualification | Forested settlement, interiors/props, underground terrain, lake, roads, entities and driving | Human checkpoint plus short automated mixed-workload tests; declared scene counts, travel route and frame/resource budgets precede performance runs |
| M5 Scale and release qualification | Increased density/distance, endurance, recovery and distributable build | Stated workloads sustain target behavior; memory/VRAM/disk growth and failures are measured; clean-machine release checks pass |
| M6 Multiplayer implementation and qualification | Authoritative session with interest-managed world/entity state | Server plus two clients and network fault tests first, then measured scaling. Architectural readiness remains a requirement throughout M1–M5 |

M6 is not authorization to market earlier milestones as completing the large-multiplayer goal. Reassess its placement after M4 before release scope is finalized. Likewise, a successful M4 scene does not prove an arbitrary city size.

## Deferred work and return triggers

These items remain open. Deferral is a scheduling choice, never a passing result.

| Open item | Why it is separated | Required return point and closure evidence |
| --- | --- | --- |
| Mining latency after travel and sustained edits | Earlier changes did not establish consistent behavior; avoid another unbounded research detour | M1 short post-flight check retains a continuity failure (328/281 ms maximum gaps); long-distance/endurance behavior remains unqualified. Return at M4, on relevant loading/interaction changes, or earlier ordinary-play blockers. Close only with repeatable response and terrain/collision agreement, including continued edits |
| Automatic model paging and checkpoint handover | Latest native infrastructure is opt-in; default world still requests block metadata only | M1 retains opt-in integration with correctness and modest rendered-route evidence. Reassess activation with M2 detailed content and M4 combined travel, before claiming detailed settlement scaling; preserve focus/save/reload/cancellation/teardown guarantees |
| Model transfer timing and arrival latency | Correctness passes do not close timing failures; the 200,000-record fixture exceeded its 2 ms gate | Before claiming detailed-world streaming capacity in M4, measure frame tails and time to usable collision/visuals at the declared travel workload; preserve failing runs |
| Terrain cache ownership, storage growth and large-world representation | Offline cleanup and existing caches are not a complete bounded runtime policy | M2 loading design and M5 endurance: stale-data rejection, quotas/eviction, disk reserve, recoverability and measured resident/disk growth |
| Dense building rendering, interiors and distant edited representation | Isolated geometry/API checks omit mixed content and actual detail | M2 representative content, M4/M5 scaling. Distant mined terrain and placed structures must remain correct; lower detail cannot silently restore the unedited world |
| Vegetation diversity and disturbance | Tree integration does not cover small plants, grass and stones | M2. Demonstrate density/LOD and local disturbance without broad unrelated disappearance; measure mixed-scene render cost |
| Entity animation, AI, collision and vehicle populations | Storage/kinematic throughput omits much of game simulation | M3 representative behavior; M4/M5 stated populations with activation/sleeping and measured CPU/GPU costs |
| Older-laptop thermal sustainability | New hardware utilization is not comparable, and short runs cannot prove sustained thermals | M5 with target hardware available or explicitly unqualified support. Keep the 60 FPS target; measure watts, temperatures, clocks and frame times where available, not utilization alone |
| Multiplayer authority and multi-world ownership | User prefers later networking implementation | Review boundaries in every relevant milestone. M6 requires real session/fault/scale tests; current single-world scene/cache ownership remains a recorded constraint |
| Fluid flow, drainage and cross-region exchange | Current water is a static connected basin model | Review after M2 static-water coverage. Keep absent capabilities explicit; do not claim mass conservation or dynamic fluid simulation. Additional fluid scope needs a deliberate design decision |
| Visual refinement and release support | Working geometry and local binaries are insufficient for a supported release | Visual feedback at each checkpoint; M5 clean-machine packaging, license notices, platform matrix and final visual regression review |

## Rules against indefinite detours

Before an investigation, record the failing behavior, smallest representative reproducer, expected result and the implementation decision it will inform. Begin with a short check; use a long run only for a question that requires duration, such as leakage or thermals.

After one investigation/implementation/verification cycle, either close the gate with evidence or state the remaining cause, next bounded experiment and effect on the active milestone. After two cycles that do not improve the gate, stop extending the approach automatically: reassess the design, retain the current working path with explicit limits, or explain the tradeoff to the user. Do not silently narrow requirements to make a test pass.

Every milestone report lists coverage gates closed, playable changes, evidence and its limits, remaining failures, deferred items whose triggers were reached, and the next deliverable. Keep the launch command and save slot available for human checks. Do not infer human acceptance from successful automated startup.

Hardware changes establish new baselines. Measurements must record build/binary identity, hardware and presentation settings; headless correctness, rendered performance and sustained thermals remain separate evidence. Preserve the 0BSD project license and dependency notices. Do not replace a working build or retag a checkpoint as good without matching evidence.

## Next concrete work

The current checkpoint is [Play Human Checkpoint.cmd](../Play%20Human%20Checkpoint.cmd), with [route and save-slot instructions](HUMAN_PLAYTEST_20261009.md). The launcher fix is commit `4ec4a08`; the older `playtest/human-20261009` tag does not include that fix.

M1 progress: [native saved-checkpoint handover](MODEL_CHECKPOINT_HANDOVER.md) now passes scene-adapter correctness checks, including dirty saves and exact edited-region retirement/readmission. Default automatic model paging remains inactive.

Native focus selection and the structures scene adapter now pass a 24-check
travel/edit/save/reload lifecycle in debug and release, including history pins and
new asset registration. [Contract and limits](MODEL_TRANSFER_SCHEDULER.md). The
fixture explicitly drains transfers; the subsequent normal-world integration
described below now supplies that barrier. The subsequent [discovery check](MODEL_FOCUS_DISCOVERY.md)
found and corrected a linear scan: 4,096 regions across 32 assets now reach the
first nearby request in one selection call instead of 2,048. Debug/release pass
50 focused checks. Full arrival, overlapping layouts and runtime performance
remain separate qualification requirements.

Normal manual saves, autosaves, reload/reset and shutdown now invoke those barriers through an opt-in main-world coordinator. Debug/release each pass 23 actual-worker lifecycle checks; the main scene passes automated 1080p startup/shutdown. [Contract, evidence and remaining decision](MODEL_PAGING_LIFECYCLE.md).

M1 disposition is recorded in [integration results](M1_INTEGRATION_DISPOSITION.md): the modest populated route passes 27 checks, including exact physics identity and distant record eviction; model paging stays opt-in because dense-content qualification remains incomplete. The existing short post-flight mining check still fails the 150 ms visible-change-gap gate (328/281 ms). Preserve this failure while advancing to M2 under the earlier decision to resume planned world work; new ordinary-play blockers take priority. Re-run continuity at M4, on relevant loading/interaction changes, or earlier human-reported regression.

M2 progress: [connected settlement authoring](CONNECTED_SETTLEMENTS.md) now generates and prepares multiple streets through the actual editor, with native layout and retained road connections. Debug/release correctness passes; a 2.002 s graphical outlier is retained. The subsequent [combined world checkpoint](CONNECTED_WORLD_CHECKPOINT.md) passes 14 fresh-process checks for exact buildings, model, roads, lakes and edited terrain, and provides a launcher for human feedback. No whole coverage row closes from this change.

M2 ground-cover work: native bounded candidate generation and renderer packing pass 17 checks in both debug and release, including all 248,982 candidate positions and restoring an individual removal into fresh native state. This is a data primitive only: visible rendering, unified interaction, authored placement, inventory transactions and actual world-save integration remain required before vegetation coverage closes. Natural identities belong to a world seed and generator version; a changed generation profile must not reuse old removals accidentally. Evidence: `docs/evidence/ground_cover_native`.

M2 ground-cover rendering checkpoint: the scene coordinator now uses three native batched collections, at most 49 nearby 32 m cells and one outstanding terrain support request. A 64-check controlled streaming test covers bounded residency, local disturbance, obsolete replies, removal retention on return and teardown. The actual-world graphical fixture passes at fullscreen 1920x1080 with a 60 FPS cap; `docs/evidence/ground_cover_stream/world.png` shows the initial simple meshes. This is test-fixture integration, not default-world activation or performance qualification. Shared surface request IDs now prevent cross-client token reuse. Next: seed/version-safe save ownership, authored placements, native picking and unified editor/gameplay inventory transactions, followed by fresh-process persistence and human checks. Do not close the vegetation coverage row yet.

M2 continues with a reproducible saved-world content route: generated terrain/geology/lake, a connected road and authored building with interior props, followed by vegetation variety and settlement generation coverage. Each change must identify which original-scope gate it closes and include a short check and a human checkpoint. M3 adds representative entity behavior and bounded vehicle populations. Review stable identity, command authority and persistence boundaries throughout; networking implementation stays later.

This task is bounded by the M1 disposition rule above. It must not indefinitely delay M2 or erase the remaining original coverage rows. No first-round completion, release date or percentage complete is claimed.
