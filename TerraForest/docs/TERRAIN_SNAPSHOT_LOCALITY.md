# Preserve snapshot geometry across unrelated density edits

The engine locality probe exposed two failed checks: a remote density edit
discarded local snapshot geometry even though a fresh post-edit build was
byte-identical. The global revision guard was safe but prevented reuse of
unaffected work. Run `python tools/probe_terrain_snapshot_locality.py --godot <exe>`.

Slots now retain both capture revision and a validated revision. The extension
observes successful command-2 edits while holding the authoritative-world lock.
It uses the edit reply's inclusive sample bounds with the existing geometry
dependency predicate. Only nonintersecting slots validated at the previous
revision advance to the new revision. An intervening intersecting or unreported
change leaves a gap and cannot be repaired by a later remote edit.

Completions retain their original `revision` and additionally return
`validated_revision` (or -1 for stale results). This preserves provenance rather
than relabeling old capture data as freshly generated. Consumers must still check
the validated revision and epoch again at publication. This certification covers
geometry only; normals, materials, lighting and other dependencies need their own
coverage before this rule can be used for complete render packets.

All 33 locality checks pass after correction. Real edits exercise a remote site,
region interior, shared edge and shared corner. Each first edit is followed by
another remote edit: unaffected work stays valid across the chain, while locally
invalidated work stays rejected. Independent fresh builds confirm equality only
for the remote case and changed geometry for intersecting cases.

Reset/load/cancellation still invalidate by epoch. Other mutation commands do
not receive locality certification. Failed command-2 edits conservatively bump
the snapshot epoch because a failure could occur after partial page changes
without a revision increment. The expanded 17 bridge checks cover rejection after
a malformed failed edit; allocation-induced partial edits are not fault-injected.
The seven native worker checks also remain applicable and pass.

Both extension variants are rebuilt. This improves the opt-in geometry path,
not the normal mining pipeline. Sustained distributed edits, normals, collision,
forest preservation and graphical performance remain unqualified.

Evidence under `evidence/terrain_snapshot_locality/` retains `before.json.gz`,
`after.json.gz`, and the follow-up bridge and native worker reports.
