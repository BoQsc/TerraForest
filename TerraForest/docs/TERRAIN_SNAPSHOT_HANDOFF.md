# Snapshot worker notification timing

Submission diagnostics now include the ready-state update, condition-variable
notification and worker mutex release as `handoff_ms`, plus a separate
`world_unlock_ms`. Native total includes world unlock. Diagnostic publication
and dictionary construction use a separate mutex after the world lock is
released, so reading last-call timing no longer acquires the world lock.

The instrumented pre-change workload captured a 7.418 ms external submission:
7.3968 ms lay in worker handoff, versus 0.0042 ms in sparse capture. This narrows
that observed outlier to the handoff interval; wall-clock timers still cannot
distinguish OS preemption from time spent executing notification/unlock.

The worker now releases its mutex before notifying. Its ready predicate and slot
contents remain published under that mutex, and the waiter rechecks the predicate
under the same mutex. This avoids waking a worker while deliberately still
holding the mutex it needs. No work, slots or quality settings are removed.

| Maximum per run | Before | After |
|---|---:|---:|
| External submit | 7.418 ms | 0.530 ms |
| Worker handoff | 7.3968 ms | 0.4969 ms |
| World unlock | 0.3856 ms | 0.0455 ms |
| Sparse capture | 0.1425 ms | 0.0549 ms |

Each run completes 640 surface jobs and 640 changing distant edits with pending
work. Queries total 7,153 before and 7,377 after. Both runs pass correctness and
the unchanged provisional call gates. These are single sequential before/after
runs, not a controlled statistical claim about tail latency or scheduling.
The older 20.351 ms capture-call rejection was not reproduced and remains an
unresolved qualification concern rather than being erased by these results.

Both extension variants rebuild. Timing metadata remains last-call state;
concurrent submitters can overwrite it before retrieval. Total native timing
excludes the final diagnostic-state publication and engine return path.
Normal gameplay, graphical performance and long-duration reliability are unchanged.

Evidence: `evidence/terrain_snapshot_handoff/before.json.gz` and `after.json.gz`.
