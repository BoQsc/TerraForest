# Native route-water footprint queries

Status: scoped CPU improvement; cold pursuit and stable 60 FPS remain open.
Implementation: `1df22d86` (debug/release libraries and matching test UID included).
Follow-up: [phase CPU-work and recorder-off controls](phase-work-2026-11-09.md)
retain the newer diagnostic package and hardware-limiting observations.
Continues [bounded model/door invalidation](navigation-model-invalidation-2026-11-09.md).
[Exact receipts](navigation-water-batch-2026-11-09.json) retain source/release
comparisons, failed attempts, native hashes and saved-world results.

## Cause and implementation

The saved tower made about two million individual water-depth calls while
validating route footprints. Each already called native code, but still crossed
the engine's Callable/Variant boundary. The native water owner now accepts a
bounded whole-footprint query, evaluating the same positions internally. The
navigator can install it alongside the point provider; zombies and the trader
use that pair. No water result is cached. Live movement observes water removal
and restoration on its next guard, even before a graph invalidation.

The nine offsets, 10 cm interval spacing, supported midpoint interpolation,
feet+10 cm probe height and positive-depth rejection remain identical. Inputs
are finite and bounded; the public batch permits at most a 2 m endpoint span.
Current route quanta are at most 1.061 m. Invalid provider return values reject.
The original point-provider API remains available, and custom admission keeps
the original interleaved point-call order. Replacing either provider invalidates
previous routes. There is no change to water storage, topology, quantities,
rendering, navigation geometry, permissions or the 750 us cooperative budget.
New code and tests are original 0BSD work; no external code/assets were imported.

## Comparisons

The fixture restores flat and sloped water cells, compares 1,500 deterministic
wet/dry footprints against individual point queries, and plans around actual
water and a solid wall. All four point–batch–batch–point runs independently clear
the graph and produce **the exact same path and 989 search-work units**. Both
source and release pass 14 assertions, including live water edits, custom
admission, invalid results and the legacy API. Separate zombie navigation passes
15 checks; the six release sampling and five release traversal fixtures pass.

| Release fixture averages | Point calls | Native batches |
| --- | ---: | ---: |
| Hazard-query wall time | 21.439 ms | 2.089 ms |
| Total planning wall time | 65.235 ms | 39.156 ms |
| Thread cycles | 152.225 million | 93.800 million |
| Planning ticks | 78.5 | 49.5 |

These are totals across an entire fixture search, not single-frame times. The
selected release comparison uses about **90% less hazard time and 38% fewer
thread cycles**. Source also reduces cycle totals, but a 9.8 ms support-query
wall-time outlier obscures part of its elapsed-time improvement. Raw cycles are
not microseconds; frequency, scheduling and host load still affect comparisons.

The actual saved tower passes **14/14** in both provider modes, including intact
door blocking/destruction, both stair flights, contact, return and a check that
the observed counters match the requested provider. Every one of the **200 save
files remains unchanged**. The batch mode makes 30,226 footprint calls versus
2,007,351 point calls in the control; internal hazard samples are retained.
Total hazard-query time changes from **1.147 s to 0.188 s** (about 84% less).

| Actual tower | Point control | Native batch |
| --- | ---: | ---: |
| First outbound path | 32.636 s | 15.603 s |
| Outbound attack contact | 99.201 s | 82.220 s |
| First return path | 48.338 s | 40.609 s |
| Return attack contact | 106.811 s | 98.857 s |

These serial runs are not a universal latency bound. The earlier batch observation
has 23.974/37.824 s first paths. Physical starting positions and later replans can
vary; exact path parity is established by the fixture, not asserted for these
full-world journeys. Cold pursuit remains unacceptable despite reduced query CPU
cost. It needs fewer sampled search candidates or prepared connectivity, while
retaining physical verification, dynamic edits and explicit unavailable states.

## Installed package and rendered checks

The export, packaged replan (14), response (11) and furnished moving-pursuit
checks (23) pass. Both furnished-room captures and both arrival captures were
inspected; no visual reduction was observed in this scope. Two fresh owned copies
of the retained default world complete normal saves and shutdown without strict
diagnostics or sampled resource-budget failures. This does not qualify long-session
leak stability. All 14 source/dist DLL hashes match. The installed PCK is
556,865,068 bytes, SHA-256
`60e22b63ebd9890d92a31b5acaa4fbcfab0c003e40048f015b9a7bbedc3b287e`.

The two rendered traces contain 1,581/1,550 unique **triggered gameplay** frames,
with p99 **25.393/25.053 ms**, maxima **34.446/36.094 ms**, and mean GPU time
**7.905/7.893 ms**. The previous single-run checkpoint was 23.210/27.710 ms
p99/maximum. These candidate tails are worse; navigation CPU savings must not be
presented as improved frame pacing. The first maximum contains a **14.786 ms save
capture** and 13.221 ms draw interval, with only 19 us navigation planning. The
repeat's maximum has 12.551 ms physics and 18.918 ms draw intervals, with only
32 us planning. Other long draw intervals reach 25.143 ms while the reported GPU
timer is 7.857 ms. Those intervals overlap other measurements, GPU timers may lag,
and triggered windows are not unbiased whole-session distributions. Scheduler,
physics, save and presentation attribution remain necessary before claiming a
cause for the increased tails.

## Failed attempts and remaining gates

- The first new fixture failed its invalid-provider assertion because it left a
  custom admission callback active. That deliberately selects the point fallback.
  Clearing that test callback exercises the intended batch rejection; no runtime
  semantics were relaxed. The failed run remains in the receipts.
- The first requested point-control world run actually used batching: asynchronous
  loading reinstalled the production provider. It is retained as a batch
  observation and excluded as a control. The driver now applies the option after
  loading and checks observed call counters before passing.
- `water_cut_cells` fails six legacy assertions in both the previous committed
  water DLL and the candidate, with identical PASS/FAIL output. This is an existing
  unresolved gate, not a pass. Reconcile its quantity/head/migration assertions
  against the current terrain-fitted water contract, then require volume/depth
  and visual evidence before changing expectations or implementation. This
  read-only footprint patch does not resolve it.

The earlier batch world run contains a **14.221 ms** navigation interval with
**zero route work and 113,726 thread cycles**. The source fixture's **9.800 ms**
support interval records 532,253 cycles. These support a wait/descheduling
investigation, not a claim that water computation caused those tails. Windows
Performance Recorder is available with CSwitch/ReadyThread profiling, but starting
the owned `CPU.Light` recording fails with `0xc5585011`: "Failed to enable the
policy to profile system performance." A subsequent status confirms it is not
recording. No elevation or system-policy change was attempted; no scheduler trace
has identified the wait owner. Exact stall attribution,
rendering/presentation costs, remaining save capture, broad edits, sustained
crowds and long-session leak stability remain open.
