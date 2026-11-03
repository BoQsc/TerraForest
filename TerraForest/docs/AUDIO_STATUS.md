# Audio foundation and first playable slice — 2026-11-03

The optional addon, versioned data-only packs, curated NOX content, surface
footsteps, forest bed and physical fire loops are implemented. This closes the
first two stages of the audio proposal within the boundaries below. The full
world soundscape and listening/performance acceptance remain open.

See the [addon/API/content guide](../addons/audio_runtime/README.md),
[replacement example](../mods/example_audio/README.md) and
[engineering evidence](evidence/audio_runtime/README.md).

## Implemented scope

- Optional session attachment; no world-save component or migration.
- Stable semantic events and caller-owned loop handles; fixed 32+4 voice pools,
  eight positional-loop cap, priority admission and cancellation-safe beds.
- Explicit startup configuration, dependencies, replacements, context selection,
  fallback, repeat avoidance, input limits and atomic external-set rejection.
- 82 NOX recordings/derivatives, 23 definitions, 4,500,376 encoded bytes; archive,
  source-member and derivative hashes plus retained CC0 evidence and credits.
- One-player actual-distance steps with floor/material lookup, bounded native
  terrain queries, fallback and pause/flight/swim/drive/teleport suppression.
- Forest-cell/roof-based ambience and bounded existing nearby fire placements,
  plus visible held torch sound. Mixer controls for addon playback.

## Required follow-up

| Requirement | Current limit and reason | Return trigger / evidence needed |
| --- | --- | --- |
| Listening acceptance | Levels, cadence, randomization and loop seams have engineering checks but no user listening approval | Play walk/run routes across materials and approach/leave fires; accept or revise recordings and mix |
| Foot-plant alignment | First slice uses actual distance; authored gait contacts vary across tools | Establish common locomotion/contact events; record synchronized first/third-person walk/run/crouch/landing evidence |
| Full terrain mapping | Natural surface fallback is grass/rock with explicit materials, water and high-altitude snow; sand/gravel/leaves need richer context | Expose existing authoritative biome/cover context without new per-frame world sampling; verify representative shores, underground and painted terrain |
| Environment transitions | Forest occupancy uses 128 m renderer cells and one roof probe, so edges/interiors are coarse | Add authoritative environment zones/time/weather context; listening evidence for edge, cave and indoor transitions |
| Other world adapters | River/stream geometry, vehicle RPM/load, character vocals, doors, tools and combat are later stage work | Connect their existing authoritative events/state to the shared API; verify activation/retirement, repetition, priority and mute |
| Existing combat mixer | Synthesized combat retains its original pool; the new Audio page currently controls addon playback | Route combat through semantic events with an explicit synthesized fallback; preserve AI hearing and damage timing |
| Dense emitter scheduling | First slice reuses native collision residency, caps fire candidates at 128 and keeps at most eight loops; candidate ordering is not a globally nearest guarantee | Native region/emitter descriptors and fair bounded selection; demonstrate dense settlements and high-speed travel without whole-world scans or starvation |
| Obstruction and acoustics | Roof probe only, without wall occlusion or room reverb | Add budgeted cached obstruction/environment policy; compare audible transitions and runtime cost |
| Larger content libraries | Startup-loaded encoded content has a 48 MiB limit; no streaming cache/eviction | A measured larger library requires it; validate memory, decode load and hitch-free prefetch/retirement |
| Representative performance | Scoped headless and graphical correctness are not old-laptop or populated travel qualification | Record audio CPU, heap, drops and frame-time deltas on target hardware with dense sources and travel |

Tests do not authorize broad claims about world acoustics or human acceptance.
Executable/native mods retain the existing explicit trust model; audio data packs
do not install scripts or native libraries.
