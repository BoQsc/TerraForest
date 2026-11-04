# Modular world audio — schema 1

Optional 0BSD addon; selected NOX recordings and original pack metadata are CC0.
The session host dynamically attaches `world_audio.gd` to the normal world after
scene creation. Delete this addon, set `terraforest/audio=false`, or launch with
`--no-audio` to omit it. There is no new world-save section. Audio preferences
live outside saves in `user://audio_preferences.cfg`; temporary/offscreen tests
do not write preferences. ESC > Audio exposes enable and category volumes.

## Ownership and runtime

Gameplay retains movement, contacts, damage, AI hearing and persistent state.
Audio never calls `hear_noise`, changes inventories or integrates bodies.
`audio_runtime.gd` owns 32 reusable positional voices and four background voices;
at most eight positional loops reserve the remaining slots for short effects.
Godot's native audio engine handles mixing, codec playback and attenuation.
No per-world-object nodes or audio simulation loop is added. Lower-priority
one-shots can be replaced when full; loops require explicit stop. Unknown events
are silent. `statistics()` reports active voices, drops, plays and content bytes.

`emit_event(event, context)` returns a generation-like monotonic playback handle,
or zero for rejection. `start_loop(event, context, background=false)` starts a
declared loop. `update_loop(handle, position, gain_db=0)` updates it; `stop(handle)`
retires it. Reused slots never reuse handles. `clear()` retires all transients.
Callers own moving loops and must update/stop them; the world adapter does so at
4 Hz. A changed terrain epoch, pause, focus loss, shutdown or disable clears
adapter-owned playback and pending queries. Short one-shots naturally finish.

The world adapter samples the one player's actual displacement at 60 Hz, emits
the first grounded step after 0.15 m, then uses 1.8 m walk / 2.7 m run intervals.
It suppresses idle, flight,
swimming, driving and teleport steps. It uses the actual floor collision, authored
block material, object material or optional `audio_surface` collider metadata.
Natural terrain requests one bounded native worker material ray per step. Playback
starts immediately using the floor estimate or a same-revision material cached
within 3 m; the reply updates the next step's cache without emitting another sound.
Stale, edited, epoch-mismatched or >100 ms results are discarded. A surface change
may use the preceding estimate for one step; worker latency never delays playback.
Explicit materials, shallow water and high-altitude snow have mappings.

Forest ambience uses existing forest-cell occupancy and one roof probe at 4 Hz,
with gradual volume changes. Fires reuse existing native collision-resident
placements: at most eight source collections, 128 total candidates and eight
positional loops. Fireplace/standing-torch/campfire asset names opt into the first
adapter; a visible held torch also requests the small-fire loop. No global model
or tree enumeration runs during play. There is no dependency on the optional
house-light addon: matching models are used only if present.

The held torch uses a -6 dB caller trim on both loop creation and updates, so
the bundled fire definition plays it at -18 dB before spatial attenuation and
bus controls. Placed fires retain the pack's gain. Replacement fire packs also
receive the held-item trim. This level was lowered on 2026-11-04; listening
acceptance remains part of the audio follow-up.

## Content and mods

The bundled pack is `packs/nox/pack.audio.module.json`. Despite the export-friendly
suffix, it is audio data schema 1, separate from executable module API 1. There
is no discovery scan and no executable module registration. Merge explicitly:

```ini
[audio]
manifests=PackedStringArray("user://mods/my_audio/pack.audio.module.json")
```

Restart the world after editing. Bundled defaults load first, then listed packs
in order. Dependencies must already be loaded. IDs use 1–96 lowercase ASCII
letters, digits, `.`, `_`, `-`. Duplicate IDs require `replace:true`; replacing
an unknown ID or replacing twice within one pack rejects that set atomically.
Invalid external sets produce a warning and fall back to the bundled pack.
Removing the bundled pack yields a valid silent system.

```json
{
  "schema": 1,
  "id": "my.audio.v1",
  "sounds": [{
    "id": "my.door.open",
    "event": "door.open",
    "match": {"material": "wood"},
    "files": ["open_01.wav", "open_02.wav"],
    "bus": "Effects",
    "gain_db": -8,
    "pitch": 1.03,
    "range": 24,
    "priority": 60,
    "limit": 4,
    "loop": false
  }]
}
```

The most specific matching selector set wins, then lexical sound ID breaks ties.
An empty `match` is a fallback for that event. Variants are equiprobable with
immediate repeat avoidance. Pitch chooses between `1/pitch` and `pitch`.
Allowed buses: Effects, Ambience, Voices, UI. Those categories currently mix the
addon only; pre-existing synthesized combat audio retains its existing owner.
Custom gameplay/vehicle modules can emit new event IDs without editing this
addon. The core does not automatically add behavior merely from a new event name.

Admission limits: 16 packs, 1 MiB manifest each, 256 total sound definitions,
16 variants per definition, eight selector fields, 16 MiB per audio file,
48 MiB total retained encoded file bytes, 120 seconds per clip. Files are checked
for size before reading, and loaded at preparation only. The current pack is
82 clips / 4,500,376 encoded bytes. This is an encoded-content budget, not a
measurement of all engine heap, decoder or output buffers. Replacement content
also counts; no runtime cache eviction is implemented.

Relative WAV/Ogg paths only; paths cannot escape the pack directory. Files named
`.wav.bin` or `.ogg.bin` contain the same codec bytes and survive the existing
exporter's `*.bin` filter without Godot audio remapping. Standard loose `.wav`
and `.ogg` mods also work. The loader admits no scripts, scenes, `.tres` or PCKs.
This restricted input path is separate from trusted executable mods and is not
a security sandbox. Reuse requires each pack's own provenance/license review.

The [example pack](../../mods/example_audio/README.md) demonstrates replacement.
[NOX notice](packs/nox/NOTICE.txt) and `packs/nox/provenance.json` retain upstream
identity, per-file hashes and conversions. Rebuild using:

```text
python tools/prepare_nox_audio.py <verified-source-archive.zip>
python tools/build_credit_notices.py
python tools/build_credit_notices.py --check
```

## Verification and remaining scope

`tests/audio_runtime.gd` covers content admission, replacement/removal, malformed
packs, variant selection, culling, handle lifetime, mute and fixed-pool overflow.
`tests/audio_world.gd` covers real session attachment, menu, floor classification,
mute, transient reset and module omission in a temporary world.
`tools/check_audio.py` runs the source suite and an isolated actual PCK export
using the repository's current export filters. It does not build native DLLs,
publish the main game or alter its distribution. World checks use fresh derived
caches via the repository runner and preserve existing saves.

This is the foundation and first playable slice. Remaining requirements are
tracked in `docs/AUDIO_STATUS.md`: animation foot-plant alignment, fuller terrain
biome mappings, precise forest/indoor transitions, water/vehicle/character/combat
adapters, obstruction filters, dense source scheduling, wider memory streaming,
representative travel timings and human listening acceptance. Passing headless
checks proves scoped behavior, not audible quality or large-world performance.
