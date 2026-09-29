# Destination progress under region memory pressure

Repeated dense travel exposed a starvation bug in the first native block pager.
The pager correctly freed a farther committed region, but continued its rolling
coordinate scan at the previous cursor. It could fill that vacancy with another
farther region before reconsidering the missing destination. Region count stayed
bounded while the player destination remained unavailable.

After a successful eviction, the native pager now restarts its bounded scan at
the nearest offsets. The same per-step limits still apply: 128 coordinate probes,
two read submissions, four outstanding reads and one region transfer. The change
does not relax committed-version checks, history protection or admission bounds.

## Reproduction and verification

`tests/block_pager_stress.gd` publishes 64 regions containing 4,096 chunks and
1,294,336 cells arranged as repeated floors, posts and roof ribs. The checkpoint
exceeds the legacy 2,048-chunk full-reconstruction limit. It restores metadata
with zero resident cells, then travels four times across all 64 destinations
using a 512-chunk runtime budget. Direction-change jumps also exercise stale
read rejection. Every arrival compares the region's exact packet digest to the
original publication. Settled-focus checks reject repeated admission/eviction.

The retained pre-fix run failed on destinations 8 and 55, each remaining missing
after a ten-second wait. Its exact-packet assertion checked only arrivals actually
reached, despite its overly broad label; the final test additionally requires
all 256 arrivals before that assertion can pass. The startup harness dictionary
type error was corrected before recording this baseline.

The corrected debug and isolated release runs each passed all 13 checks and
all 256 arrivals. Both reached a maximum of 512 resident chunks and four pending
reads, discarded 41 stale results, and reported zero read failures. They saved
the partially resident world and drained all requests on shutdown.

| Recorded quantity | Debug | Release |
| --- | ---: | ---: |
| Scene-step samples | 1,352 | 1,353 |
| Scene-step median | 0.069 ms | 0.067 ms |
| Scene-step p95 | 1.392 ms | 1.327 ms |
| Scene-step maximum | 2.312 ms | 2.308 ms |
| Arrival maximum | 34.578 ms | 34.525 ms |

Arrival timing includes process-frame scheduling and destinations already loaded;
it is not disk latency or a vehicle streaming guarantee. Scene-step time excludes
disk-worker time. These are short Windows headless runs of native cell storage
and paging, with no rendered buildings, physics, terrain streaming or multiplayer.
A live pre-fix process sample showed 99,463,168 resident bytes and a 113,823,744-byte
peak working set, including engine and fixture setup; this single sample does
not establish steady-state memory or a memory-leak bound.

Evidence is retained in `evidence/region_pager_pressure`. The clean package suite
also runs this stress fixture. See [native paging](NATIVE_REGION_PAGING.md) for
ownership and data-safety contracts. Dense rendered-city latency, multi-hour
memory trends, building LOD, model-region paging and high-speed readiness remain
unfinished.
