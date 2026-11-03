# Footsteps lag behind movement onset

- Status: Improved-partial / scoped engineering verification.
- Updated: 2026-11-03. Fix: shorter lead-in and asynchronous material cache.
- User review: Original delay reported; revised listening feel not yet reviewed.
- Symptom: The player starts moving before the first footstep is heard.

## Evidence

This is an audible timing issue; screenshots do not demonstrate the symptom.
The original implementation is preserved at `172a5afb`. It waits for 1.8 m of
walking (about 327 ms at 5.5 m/s), samples every 50 ms, and may wait up to another
100 ms for terrain material. Selected grass recordings begin within 2–10 ms of
the file start, so source padding is not the main cause.

The new first-step threshold is 0.15 m. At normal walking speed, the 60 Hz cadence
fixture triggers on the second tick (about 33 ms), while subsequent steps retain
the existing walk/run stride. Surface lookup updates a bounded nearby cache;
it cannot delay the current step or emit a duplicate when the reply arrives.
This is scheduler timing, not a measurement of end-to-end speaker latency.

See `source.log`, `packed.log` and `world.log` for final checks. Tests cover prompt
walking/resume onset, preserved continuous cadence, idle/airborne/teleport gates,
actual floor playback in the same call and late-reply cache-only behavior.
Source and isolated exported runtime suites pass 49 checks each; the real-world
suite passes 16 checks. The full local game pack is refreshed and checked with
the same world suite; `full-pack-world.log` retains its result.
An initial adapter parse check failed on an inferred boolean type; the explicit
type correction passes the engine parser and the final world checks. Its earlier
diagnostic is retained in `initial-adapter-parse-failure.log`.

## Remaining / resume here

Player listening approval remains open. Compare start/stop walking and running
on grass and wood; confirm that the lead-in feels responsive without extra taps.
If lag persists, measure output-buffer latency and animation/contact alignment.
The material cache can use the previous surface for one step at a boundary.
The broader [audio requirements](../../docs/AUDIO_STATUS.md) remain open.

## Reproduce / history

Open a world, stop, then walk forward and listen for the first step. Repeat with
short movements and running. Existing saves require no migration.
The source/PCK cadence tests use fixed movement distances and the world check
uses a temporary world and a unique derived cache, preserving player saves.
