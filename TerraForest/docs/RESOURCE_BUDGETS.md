# Resource budgets

Agreed 2026-10-28. Machine-readable thresholds: `tools/resource_budgets.json`.
These are regression gates, not claims that every workload or minimum-spec PC
has been qualified. No visual quality, world density or draw distance is reduced.

| Resource | Warning | Limit / policy |
| --- | --- | --- |
| Dedicated GPU allocation for the game process | 3.5 GiB | 4 GiB target |
| Process private committed RAM | 4 GiB | 6 GiB, provisional |
| Redistributable game content and bundled libraries | 4 GB | 5 GB |
| Recognized rebuildable terrain cache, all game-data cache roots | — | 2 GiB maintenance quota |
| Registered failed-check cache data | — | 1 GiB retention quota |
| Saved worlds, backups and associated data | 10 GiB total | Warning only; never auto-delete or refuse a player save |
| Successful unique temporary-check cache | — | Remove after the check completes |
| Free disk space before automated game checks / exports | — | Keep 10 GiB, plus export staging space |

GB means decimal bytes; GiB means 1,073,741,824 bytes. The 5 GB content limit
does not include developer Git history, source, compiler/import caches, reports,
player worlds or world backups. The current installed pack/libraries are far
smaller than the development directories. Those directory sizes must not be
presented as the game's install requirement.

## Enforcement and interpretation

- `tools/run_godot_check.py` and callers of its shared `execute` runner sample
  Windows process-private memory, peak working set and process-specific dedicated
  GPU allocations every 0.5 s. RAM/VRAM limit violations fail the check; warnings
  are printed and retained in its manifest. There is no in-game sampling loop.
- `tools/profile_runtime.py --require-resource-budget` also fails if complete
  RAM/GPU telemetry is unavailable. Ordinary headless correctness checks can pass
  without GPU measurements, but are explicitly not memory-qualified evidence.
- GPU measurement uses Windows GPU Process Memory counters, not whole-device
  `nvidia-smi` usage that includes other apps. Dedicated allocations across
  adapters are summed conservatively. Sampling can miss brief GPU peaks; driver
  overhead, resource eviction and true 4 GiB hardware still require testing.
- Process RAM includes native allocations, unlike Godot's static-memory counter.
  The RAM numbers are provisional engineering thresholds, not an established
  system-RAM requirement. Do not recommend a minimum system configuration from
  the current 16 GiB test machine alone.
- Export checks the prospective pack plus external runtime files against 5 GB.
  `python tools/check_resource_budgets.py` checks the installed content and disk
  reserve without launching Godot. Developer source/addon archives are separate.
- Completed checks remove only their unique, declared temporary cache. Failed
  checks retain logs, screenshots and world evidence. When their registered cache
  quota is exceeded, only old verified TRC mesh packets are pruned; unknown files
  remain and an unreclaimable overage stays visible.

## Offline maintenance

Close Godot, then run `python tools/storage_maintenance.py --apply --offline`.
Without `--apply` it only inventories candidates. It acquires each native-compatible
cache lease, validates path layout, file identity, mesh header and full SHA-256
before removing a packet. Changed, corrupt, linked or unknown files are retained.
The `worlds`, logs, generation reports and screenshot folders are excluded.
Receipts stay under `reports/storage_maintenance/`.

This global quota is checked during maintenance, not by scanning all caches on a
gameplay frame. Use `python tools/check_resource_budgets.py --storage` for a complete
read-only quota check. Legacy/manual launchers that bypass the shared check runner
are not automatically monitored or registered; maintenance catches recognized
cache growth from them. Per-cache live terrain limits still apply separately.
Source history, editor caches, system pagefiles and unrelated applications are
never automatic victims of these quotas.

Terrain caches shorten some repeat loads and rebuilds, but hundreds of duplicate
automated-test caches do not improve gameplay FPS. Removing them can make the
next affected load rebuild meshes; it does not remove source assets or saved
worlds. Git history and diagnostic images serve different purposes and are kept.

The 2026-10-28 cleanup recovered approximately **53.3 GiB net**, leaving **54.2 GiB
free**, not the requested 100 GB. The final read-only check finds 2,147,458,129
recognized cache bytes, below the 2 GiB quota. One invalid 1,041-byte packet was
retained rather than deleting unknown data. All 11.37 GiB of world-associated data
remains, with a warning only. Git, reports/review evidence, compiler/editor caches
and system/app history remain intact. Compiler-cache removal was declined by the
execution environment and was not counted as reclaimed space. More free space
needs a separate approved cleanup/archive decision, not silent removal of saves
or history. [Machine-readable evidence](../issues/runtime-performance/resource-budget-evidence.json).

## Qualification still required

On 2026-10-28, two installed-pack seed-1703 walking checks stayed within the
sampled budgets: peaks across the runs were 3.94 GiB private commit, 2.19 GiB
working set and 1.65 GiB dedicated GPU allocation. The second run also verifies
the launcher's actual isolated cache path and automatic removal. Installed game
content/libraries total 422,619,887 bytes. These are short current-build results,
not maximum-city/generation or physical 4 GiB-card qualification.

Raw manifests: `reports/runtime_performance/20261028T191224385658Z_resource_budget/`
and `reports/runtime_performance/20261028T191713499625Z_resource_budget_isolated/`.

Repeat the resource-gated walking profile on the installed build, then maximum
cities, generation/loading, long mining, driving and multi-hour travel. Record
the actual binary hashes, workload and peaks. A short run below 4 GiB is not proof
that every scene runs safely on a 4 GiB card; test that hardware before publishing
minimum requirements. Return here when adding assets, larger worlds or more actors.

The existing source/addon-bundle suite separately fails eight dependency
assertions in unchanged packaging declarations. This is not a failure of the
installed game-size gate and is not fixed by these budget tools; see
`reports/resource_budget_unrelated_package_tests.log`.

Windows API references: [counter arrays](https://learn.microsoft.com/en-us/windows/win32/api/pdh/nf-pdh-pdhgetformattedcounterarrayw),
[language-neutral counters](https://learn.microsoft.com/en-us/windows/win32/api/pdh/nf-pdh-pdhaddenglishcounterw).
