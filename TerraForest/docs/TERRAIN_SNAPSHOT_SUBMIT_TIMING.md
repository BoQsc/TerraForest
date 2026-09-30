# Snapshot submission timing breakdown

`experimental_snapshot_submit_timing()` returns the last structurally valid
submission's token, acceptance, total native wall time, authoritative-world lock
wait, worker startup interval, worker lock wait and capture interval. Values are
protected by the world mutex. This is a last-call diagnostic, not a per-caller
history; concurrent submitters can overwrite it. The load probe has one submitter
and checks token/acceptance identity for every measurement.

The sustained edit probe records this alongside its external GDScript call time.
The getter is invoked after the measured submit call; it adds observer work and
is not part of the measured submission interval. The stage timers measure wall
time, not CPU execution or scheduling events. Uninstrumented dispatch, notification,
unlock and return intervals can contribute to the difference between totals.

The new run completes 640 surface jobs, 640 changing edits and 8,471 queries with
no correctness or provisional call-latency failures. It does **not** reproduce
the prior 20.351 ms rejection and does not supersede that retained failure.

- Slowest external submit: 5.742 ms; that call's native total is 0.054 ms and
  capture interval is 0.0528 ms.
- Maximum native total across submissions: 3.0586 ms.
- Maximum world-lock wait: 0.0085 ms; worker-lock wait: 0.0004 ms.
- Maximum capture interval: 0.1612 ms; startup interval: 0.0409 ms.

Some native totals also exceed the sum of named stages, so the observation does
not prove that all unexplained time occurs in Godot. These measurements provide
no evidence of a long lock wait in this run. They do not establish the cause of
the original failure or justify weakening the gate. Further investigation must
correlate a reproduced outlier with dispatch, handoff and thread scheduling.

Both extension variants contain the instrumentation. Normal gameplay is unchanged.
No rendering, FPS, residency or endurance qualification is added.
Evidence: `evidence/terrain_snapshot_submit_timing/terrain_snapshot_edits.json.gz`.
