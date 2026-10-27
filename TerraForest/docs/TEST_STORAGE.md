# Development test storage

- Audit date: 2026-10-27. Read-only report: `reports/first_person_storage_audit.json`.
- TerraForest project: 13.86 GiB; Git history: 3.57 GiB; main game user-data folder: 76.90 GiB. These are scoped logical-file totals, not an audit of everything on C:.
- The installed game folder is 0.42 GiB. Project storage includes reports 5.45 GiB, Godot imports 2.59 GiB, documentation/evidence 2.31 GiB and native builds 1.74 GiB.
- 316 cache folders totaling 30.36 GiB match retained temporary-test run manifests. Of these, 200 folders totaling 18.37 GiB belong to successful tests. Remaining data is not automatically classified as disposable.
- User approved removal of **successful-test caches only**. Played worlds (6.91 GiB), failed-test evidence, Git, source and review images must remain untouched.
- Completed the approved cleanup on 2026-10-27: all 200 audited successful-test caches (18.37 GiB) removed; none of those target folders remain. Played worlds, failed tests, Git, source and review images were excluded. Receipt: `reports/successful_test_cache_cleanup_20261027.json`.
- C: free space increased from 303 MiB to 19.03 GiB during cleanup; free-space changes also include other system activity. `python tools/prune_successful_test_caches.py` revalidates the fixed approved audit and defaults to dry-run; `--apply` is idempotent. It refuses linked paths and changed provenance and targets only direct named cache folders.
- `tools/check_first_person.py` now removes its own fresh UUID cache after each successful check, records that removal in `run.json`, and retains logs/images. Failures and `--keep-cache` runs retain their caches. Three cleanup unit tests cover scoped deletion, unsafe names and idempotence.
- Global retention across other test runners remains unimplemented. The audit-based cleaner deliberately does not expand its approved list. Future retention work must preserve failed-run diagnosis and publish accurate cleanup receipts rather than leaving manifests implying deleted caches are still retained.

The historical first-person comparison reuses unchanged binary assets/imports
through verified local hard links, while original scripts come from Git objects.
This avoids another multi-GB asset copy. Directory-size tools may count the same
hard-linked asset twice; actual disk free space is authoritative for capacity.
