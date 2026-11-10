# TerraForest generated-artifact backup

Status: complete, remotely hash-verified project artifact backup (2026-11-10).

The primary catalog contains 176,969 files / 33.183 GiB logical content in 50 deduplicated ZIP volumes (17.405 GiB uploaded). The supplemental catalog adds 12,909 files / 1.186 GiB logical content in two volumes. Identical file contents occur only once per catalog. Sources, generated worlds, reports and native build evidence keep their original licenses and provenance. This is archival evidence, not an FPS-qualified release.

Large objects are attached to authenticated **draft backup releases**, keeping binary bulk out of Git history:
- Primary tag: `backup/generated-artifacts-2026-11-10`, release ID 440044185.
- Extra worlds tag: `backup/generated-artifacts-2026-11-10-extra-worlds`, release ID 440075503.

All 55 assets passed remote size and SHA-256 checks. `restore_verification.json` records a real GitHub download and full reconstruction of all 16 objects in one primary volume. Earlier local world/build reconstruction checks also passed.

Private conversations, account credentials, rebuildable compiler/import caches, linked targets and unmatched player saves are excluded. Player saves remain local. See catalog exclusions. Worktree commit identities and branch ownership are in `worktrees.json`; branches are retained.

## Restore selected evidence

Use the Python standard-library helper from this branch. Run from TerraForest, using GitHub authentication already configured for Git. Use a narrow catalog prefix to avoid restoring every duplicate. Download and restore primary/supplement volumes into separate folders because volume filenames repeat.

```text
python tools/generated_backup.py download ../generated-backup/catalog.json.gz ../generated-backup/upload.json.gz C:/restore-volumes-primary --prefix project/reports/performance_changes/
python tools/generated_backup.py restore ../generated-backup/catalog.json.gz C:/restore-volumes-primary C:/restored-primary --prefix project/reports/performance_changes/
```

For extra worlds substitute `extra-worlds-catalog.json.gz`, `extra-worlds-upload.json.gz`, separate destination folders, and a `userdata/worlds/<slot>` prefix. The restore destination must not exist. Download verifies remote and local volume hashes; restore verifies each reconstructed file. Do not restore directly over live saves.

The original catalog SHA recorded in upload receipts identifies the local-source catalog. Portable catalog files retain the complete file/object/directory mapping while replacing machine-specific root values with labels. `.cold-archive-20261110.json` pointers beside retired local outputs record the corresponding logical path, checksum and backup tag.

Final frozen-driver audit supplement: `frozen-worlds-catalog.json.gz` and `frozen-worlds-upload.json.gz` preserve eight additional packaged-test worlds (4,346 files / 0.490 GiB logical content in one volume), tag `backup/generated-artifacts-2026-11-10-frozen-worlds`, release ID 440099563. Use separate download/restore folders as with the first supplement.

Retention update: `retention-update-catalog.json.gz` / `retention-update-upload.json.gz`, tag `backup/generated-artifacts-2026-11-10-retention-update`, release ID 440109288, adds two volumes containing the new local archive chunks/manifests and retirement receipts. This closes metadata gaps found in the raw-world inventories. Restore primary and this delta into separate new directories, then combine disjoint chunk filenames in one inspection store; the primary catalog holds the unchanged earlier chunks. Archive manifests retain full logical-file SHA-256 values and ordered chunk identities.

`cleanup_summary.json` records 161 archived test worlds, 11 frozen builds, 12 regional caches and four retired worktrees. Net tracked logical bytes reclaimed: 49.749 GiB, excluding Git packing and temporary restore checks. The volume had 50.490 GiB free at final verification. Every development-output category, including next-capture allowances, passes admission. Windows refused removal of nine small backed-up media files; these remain recorded.

`remote_world_restore_verification.json` proves complete-world reconstruction (305 files / 62,205,099 bytes) from an actual GitHub download, independently of local source files. `final_remote_verification.json` records size/digest checks for all 55 assets.
