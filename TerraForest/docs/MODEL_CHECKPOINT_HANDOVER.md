# Model checkpoint handover

2026-10-09. The archive now exposes committed model-region notices, and the shared
model scheduler can adopt a newer saved checkpoint without losing the backing data
of unloaded regions. This closes a native prerequisite within M1 of the
[delivery plan](PROJECT_PLAN.md). Automatic scene paging remains unfinished.

The notice and replacement lease are acquired together under the archive queue
lock, preventing save cleanup between observation and retention. Handover validates
every unavailable region against the new committed index. It preserves the old
lease on incompatibility, active work or retention pressure. Publication notices
change only after successful root publication and share the block notice revision.
The implementation is project-owned 0BSD; no save format or dependency changed.

## Verification

The existing `model_world_bootstrap.gd` fixture uses the actual structures scene
capture/restore adapter, two populated assets, a newly registered empty asset and
12,000 placements. Debug and release pass 44 checks. The added cases cover:

- Metadata startup and selective admission followed by a resident edit and partial save.
- Pending/unpolled job rejection and replacement-lease capacity backpressure.
- Releasing rendering/collision residency after focus moves away, then retiring and
  readmitting the edited region from the new checkpoint with byte-exact equality.
- Rejecting a saved version that changes an unavailable region, preserving the
  previous version for exact admission, and subsequently saving/handover again.
- Atomic notice retention, caller mutation isolation, rejected-save notice stability,
  archive release, and compatibility with the default full-model loader.

Release regressions also pass 82 compound archive, 42 scheduler and 34 checkpoint
retention/provenance checks. [Logs, reports and DLL hashes](evidence/model_checkpoint_handover/)
identify these builds. The initial fixture failure is retained: it attempted to
retire a still-rendered region, which the native guard correctly rejected. The
corrected fixture moves rendering and collision focus away and verifies residency
is zero before retirement. The guard was not relaxed.

These are short headless correctness checks. Focus movement is scripted at the
collection level; this is not player travel through an automatic scene coordinator.
No current GPU, FPS, dense-arrival or thermal improvement follows from these tests.
The previously failing dense-transfer timing gate remains open. Handover scans up
to 4,096 region entries for one collection synchronously and has not been qualified
as a hard frame-time bound.

## Next integration work

Connect per-asset focus selection and save-completion handover to the scene lifecycle,
including drain/retry during reload and shutdown. Maintain the existing default
path until the combined coordinator is tested. The new handover API does not by
itself complete that milestone or enable metadata-only startup in the default game.
