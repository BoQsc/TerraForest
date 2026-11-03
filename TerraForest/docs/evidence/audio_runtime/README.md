# Audio foundation verification — 2026-11-03

Godot 4.7.2 stable, Windows x86-64. All checks use the real engine.

- Source catalog/runtime: **41 checks, zero failures**, including cancellation
  before background playback, normal background playback, replacement/removal,
  malformed packs, fixed voice/loop capacities and immediate mute.
- Isolated PCK exported with the repository's current filters: the same
  **41 checks, zero failures**. No main-project native builds or preset changes
  are required by that fixture.
- Real world: **13 checks, zero failures**, including session attachment, menu,
  floor collision/material, mute, reset and actual held-torch activation/retirement.
- `--no-audio` real world: **2 checks, zero failures**. World reaches play with
  the addon omitted.
- Existing native zombie awareness regression: **34 checks, zero failures**.
- Full local TerraForest pack exported successfully, passed its existing startup
  and house-light gates, then passed the **13-check audio world suite** using
  the packaged game resources and matching external native libraries.
- Credits freshness, startup-index freshness, Python compilation and diff
  whitespace checks pass.

`source.log`, `packed.log`, `world.log`, `omitted.log` and `awareness.log` retain
the scoped outputs. `audio-menu.png` is the inspected 1920x1080 Audio page;
controls fit without clipping. It does not establish listening quality.
`full-export.log`, `full-pack-world.log` and `evidence.json` record the refreshed
local distribution and its identity. No new executable/native binary is authored
by the audio change; the existing launcher uses the refreshed pack.

Earlier failed evidence remains: `initial-world-failure.log` records the test's
nonexistent entry-camera `cancel` call, corrected to the existing `finish` method.
`initial-loop-leak.log` records immediate background-loop cancellation exposing
four leaked WAV playbacks. Background admission now defers playback behind a
cancellable handle; pending slots count toward capacity. The regression tests
cover cancellation before start and normal playback after start. Leak warnings
fail the check tool. The passing final logs contain no leak warnings.

Run source and PCK checks:

```text
python tools/check_audio.py --godot <engine-executable>
python tools/run_godot_check.py audio_world --godot <engine-executable> --headless --timeout 110 --require "AUDIO_WORLD checks="
python tools/run_godot_check.py audio_world --godot <engine-executable> --headless --timeout 110 --require "AUDIO_WORLD checks=" -- --no-audio
```

Temporary-world tests and unique derived-cache paths preserve existing saves.
The [open requirements](../../AUDIO_STATUS.md) include human listening,
representative performance, precise environment mapping and the later adapters.
