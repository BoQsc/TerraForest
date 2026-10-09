# Model paging in the normal world lifecycle

Updated 2026-10-09. Automatic model paging is integrated behind
`--model-region-paging`. The default and human-checkpoint launch paths retain full
model loading while populated-world arrival and frame costs remain unqualified.
This closes the normal save/reload wiring task, not the dense-world performance gate.

From the project directory:

```text
python tools/run.py --slot model_paging_trial --model-region-paging
```

Use a separate slot for qualification. The flag enables metadata-only model startup
and `addons/structures/model_paging_coordinator.gd`. That adapter handles lifecycle
transitions; native code still selects regions, indexes bounds, reads packets and
advances transfers. It uses the existing editor history and player focus.

## Lifecycle contract

- Manual save requests remain queued while transfers cancel/drain across frames.
  Autosave uses the same gate. Capture and worker submission happen after draining.
- The backend reports save completion with a structured success flag. Successful
  publication permits checkpoint adoption and resume. Rejected capture preserves
  the previous canonical file and releases the save wait; it does not advertise a
  successful save. Queue rejection does not create a completion wait.
- Reload/reset wait behind an accepted save and pending transfers before replacing
  collections. Restore re-enables model paging against the restored checkpoints.
- Normal asynchronous shutdown drains before the final capture. The existing
  30-second shutdown deadline also covers this wait. Failure disables new snapshot
  writes and retains the previous canonical save. Direct exceptional teardown
  retains the same protection and native synchronous cleanup fallback.
- The coordinator starts one archive read service with a 16-request / 64 MiB
  reservation bound. The block pager borrows an already-running service without
  restarting or stopping it. Standalone block-pager ownership remains supported.
  The archive owner must outlive both consumers and stop the service at teardown.

## Evidence

`tests/model_paging_lifecycle.gd` uses the actual terrain worker and persistence
coordinator, two assets with 512 placements each, and separated near/far regions.
Debug and release each pass 23 checks: automatic retirement, travel requests,
manual save during transfers, edit/autosave, rejected capture, reload behind a save,
shutdown persistence, fresh archive/scene reconstruction, and reset. No test-driven
calls drain or advance transfers; the same coordinator used by the game does that.

Release regressions pass 29 block-pager checks and 76 regional structure-persistence
checks. The main scene passes automatic graphical startup/shutdown with the flag,
1920×1080 fullscreen, 100% render scale, VSync and a 60 FPS cap. Its screenshot was
inspected for scene/UI rendering. This new-slot scene is not a populated-model
travel test, a human playtest, sustained FPS proof or a thermal measurement.

[Reports, logs, screenshot and build identity](evidence/model_paging_lifecycle/).
Run the release lifecycle fixture using `tools/test_native_release.py --addon
structures --test model_paging_lifecycle --godot PATH`.

## Remaining decision

Keep the opt-in path available, but do not enable it by default from these results.
The earlier dense transfer timing failure remains open; see
[scheduler evidence](MODEL_TRANSFER_SCHEDULER.md). [M1 disposition](M1_INTEGRATION_DISPOSITION.md) retains opt-in operation after a
modest populated route passes. Broader activation still needs
a short populated-world travel/edit/save/reload route with visual/collision arrival
and frame-tail measurements. If that gate fails, retain the current default and
record the limiting workload before proceeding with M2 content coverage. Do not
turn this into another unlimited prerequisite for building missing world systems.

This work does not resolve terrain mining latency, provide network replication,
change the save format, or add a dependency. Project code remains 0BSD. Stable asset
and placement identity and committed checkpoint boundaries remain available for
later authority/replication design; they are not multiplayer qualification.
