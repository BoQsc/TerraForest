# Prefab publication correctness — 2026-10-15

Reproducer: a valid one-cell native prefab with 9 MiB authoring metadata. Before
the fix, _save_asset returned success and appended it to the active library,
although _read_asset rejects files larger than 8 MiB. Reopening silently omitted
the asset. The before log fails the rejection and cleanup checks.

Both synchronous authoring and the asynchronous frontage worker now share a
verified write helper. It saves into a `.pending` subdirectory outside the active
nonrecursive resource scan, applies the existing size/type read boundary, checks
exact cell records, attachment transforms, name and metadata, then renames to the
new final path. Failure removes its pending output and does not append an asset.
Existing final paths are rejected. This changes no per-frame world persistence.

After: oversized publication rejects and leaves neither files nor staging
directories; a valid layout reopens with exact geometry and road metadata.
Existing prefab-library regression covers capture, rotated placement, archive,
restore, stack and frontage. The 26-check settlement network suite passes,
including actual asynchronous saved generation and road persistence.

Limits: no disk-full fault injection, process-kill durability/fsync proof or
multi-process writer qualification. A crash may leave a staging directory, which
the active library ignores; automatic stale staging cleanup is not implemented.
This does not raise the per-resource size or native composition limits.
