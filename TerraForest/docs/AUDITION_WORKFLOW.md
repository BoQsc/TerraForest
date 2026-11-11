# Live sound audition workflow

How we choose and tune game sounds by ear, while the game is running, without
relaunching for every candidate. Written from the code path that actually runs
(`world_audio.gd`, `kaino_audition_map.gd`), not from intent.

## Why it exists

Picking a sound by listening to a file in a player does not tell you whether it
works **in the game**. Clip length, level against other sounds, and how it lands
with an animation only show up in play. Judging in-game normally costs a relaunch
per candidate, which is too slow to iterate. This workflow removes the relaunch.

## How it works

1. Every sound is an **event id** resolved through the audio catalog, e.g.
   `flesh.hit`, `world.break.wood`, `zombie.vocal.idle`.
2. A one-shot is decoded to PCM at load time and stored as a `:once` stream; a
   looping sound as `:loop` (`kaino_audition_map.gd`).
3. The audition selection (`kaino_audition_selection.json`) maps an event id to a
   replacement file. `WorldAudio.reload_mapping()` re-reads it **once a second**
   and only when the file's modified time changes (`RELOAD_SECONDS`, line 110).
4. On change it restores each sound's original `files`, then applies the
   selection over the top. So removing an entry reverts to the shipped default —
   the selection is an overlay, never the source of truth.
5. The game's own log records every event and the file it resolved to:
   `user://audio_events.log`. This is how you confirm a live change took effect.

## The loop we actually use

1. Put candidates where Godot can read them (under `res://`). Convert non-PCM
   sources first — the runtime decodes PCM WAV only.
2. Add one line to the selection:
   `"flesh.hit": "res://…/candidate.wav"`.
3. Hit the thing in-game. Within about a second the new sound plays.
4. Swap the line for the next candidate. No relaunch at any point.
5. When something works, promote it: copy the file into the pack directory, point
   the pack manifest at it, and delete the selection override so the shipped
   default is authoritative.

## Rules learned the hard way

- **A running game reads the manifest once at startup.** Editing the pack manifest
  alone changes nothing until relaunch. Promote through the selection override
  first, then it takes effect live.
- **Only the recording changes live.** Gain, range, priority and loop come from
  the manifest at load. To change level live, prepare a levelled copy of the file.
- **The selection is an overlay.** If an entry disappears, that event silently
  reverts to its shipped default — which looks like "my change was ignored".
- **Confirm from the log, not from intent.** `audio_events.log` shows the exact
  file each event resolved to; a `mapping N entries …` line marks each reload.
- **Keep audition files out of shipped pack folders.** Scratch candidates belong
  in a build area (`.build/`), with only approved clips copied into
  `addons/…/packs/…`. Use the selection to point at them while auditioning.
- **Record every verdict.** Declined sounds get listed so they are not proposed
  again — see `docs/FLESH_HIT_AUDITION.md` for the format.

## What is still Kaino-specific

The mechanism is generic (any event id, any file). The naming is not: the map
class and its file are called `kaino_audition_map` / `kaino_audition_selection`,
after the pack it was first written for. That is a rename, not a redesign, and is
worth doing when this workflow is next touched.

## Checking it without playing

`tests/flesh_live_map.gd` loads the real packs, applies the selection through the
real map, and asserts the event resolves to the expected file and decodes as WAV
PCM. That catches a broken selection without a game session.
