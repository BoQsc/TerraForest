# Existing publication path: retain with targeted hardening

A clean headless Godot 4.7.2 release-DLL probe exercises the real stream's mesh
upload, native collision recipes, collision cooking, staging, activation and
batch commit. Four 16 m regions meet at (1296,1296); a radius-4 excavation changes
all four. The probe runs in approximately 1.4 seconds including process startup.

**35 checks pass after one transaction fix.**

- Old visuals and colliders remain active while each replacement is prepared.
- Physics rays at four points adjacent to the common corner continue to hit the
  original bodies at identical heights before commit. Hidden prepared bodies do
  not participate in those queries.
- A matching completion publishes all four replacements; subsequent physics
  queries hit the replacement bodies and lower excavated surfaces at all points.
- Obsolete epochs/stamps cannot clear a newer in-flight request. Invalidating an
  entry during preparation discards it without replacing the active entry.
- An obsolete completion ticket cannot publish the batch.
- A duplicate matching completion previously committed again, incrementing the
  published revision and emitting publication side effects a second time. The
  completion handler now requires an edit still to be pending. The regression
  reproduces the failure before the fix and passes afterward. The production
  worker is not known to deliver duplicates; this is adversarial hardening.

## Scope and decision

Retain the staged visual/collision swap as a candidate building block for local
reconstruction. There is now narrow evidence for reuse rather than a reason to
rewrite it wholesale. This does not resolve the existing mesh topology failures,
large enclosing rebuilds, lighting scope or expensive distant simplification.

The test replaces only the coverage planner's `_update_cut` with a fixed four-tile
cut. It drives worker-result delivery explicitly without starting a worker. It
therefore does not qualify whole-world coverage, mixed LOD transitions, queue
fairness, scheduling latency or concurrency. The completion-after-preparation
ordering is tested; other delivery orderings require additional coverage.

Headless mesh upload timings are diagnostic only. They do not measure GPU work,
fullscreen frame pacing or interaction latency. Physics rays verify engine
collision queries after physics steps, not player locomotion, tunneling or every
surface point. No new mesher is integrated and no production-scale claim follows.

Reproduce:

```text
python tools/probe_terrain_publication.py --godot PATH
```

The runner copies the release DLL and scripts into an isolated temporary project,
rejects script errors and object leaks, and retains source/DLL hashes. Evidence,
including the pre-fix duplicate-completion failure, is under
`docs/evidence/terrain_publication/`.
