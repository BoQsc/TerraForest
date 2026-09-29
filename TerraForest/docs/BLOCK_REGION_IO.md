# Native background block-region I/O

`NativeBlockRegionIO` owns one persistent C++ worker and one
`NativeBlockRegionStore`. Disk opening, catalog parsing, packet validation,
publication, reads and collection execute on that worker. Its API does not access
the scene tree. Capture, restore, unload and residency decisions still belong to
the scene owner. This is an opt-in paging component; automatic travel paging and
catalog-aware compound world saves remain unfinished.

## Requests and completions

Call all public methods from one owner thread, normally the scene thread. Do not
use concurrent lifecycle calls. `start(absolute_directory, request_limit,
byte_limit, recover_backup=false)` starts the worker and returns a positive ticket,
or zero for rejected configuration/state. Directory opening itself is asynchronous.
Its completion contains `operation="open"`, `ticket`, the store status fields and,
on success, `keys`: sorted packed xyz triples from the catalog. Only after a
successful open is the queue ready for more work. A failed open releases the
store and terminates the worker; consume its completion before restarting.

The following methods return positive tickets for accepted requests, or zero
without scheduling work. Treat zero as rejection, never as a persistence success.

| Method | Worker operation |
| --- | --- |
| `publish_regions(packets, expected_checksums)` | Conditional atomic catalog batch, with normal store validation |
| `read_region(region)` | Validated packet read; absent/corrupt data is a failed completion |
| `remove_region(region, expected_checksum)` | Conditional catalog removal |
| `list_regions()` | Current sorted catalog keys |
| `collect_garbage(max_inspected)` | One bounded store-maintenance step |

Accepted requests execute FIFO. `poll(max_results=16)` transfers at most 1–64
completion dictionaries to the caller. Every accepted request retains exactly one
completion, including failures. Each includes its `ticket` and `operation`, plus
the synchronous store result; reads/removals also include `region`. Invalid poll
limits return an empty array without consuming anything. There are no callbacks
from the worker. Ticket numbers increase across restarts of the same object.

Publication captures independent Array containers holding copy-on-write packet
and checksum values. Caller mutation after acceptance cannot alter the queued
request. Basic types, sizes and checksum lengths are checked during admission;
checksums, packet semantics and expected versions are verified on the worker.
The packet capture itself remains a bounded main-thread block-world operation.

## Backpressure and accounting

Configure 1–256 outstanding requests and 2–256 MiB of payload reservations.
Outstanding means queued, active **or completed but not yet polled**. Thus an
application that stops consuming results cannot accumulate an unlimited queue.
Requests over either budget return zero immediately; consuming results makes
capacity available again. No accepted write is dropped to admit a later request.

Reads reserve the maximum 2 MiB packet output before I/O. Open/index requests
reserve 786,432 bytes for the maximum 65,536 xyz triples. Publications reserve their
input packet and expected-checksum sizes (up to 64 packets, 64 MiB combined).
Removal reserves 32 checksum bytes; collection has no variable byte payload.
Reservations remain charged until polling, even if the result is small or fails.
This is intentionally conservative.

The byte budget is **not a total process-memory cap**. It excludes bounded request
and result metadata, store catalog metadata, transient validation/commit scratch,
the thread stack, allocator overhead, and data retained by the caller after poll.
The underlying store still rewrites catalog metadata per committed batch. Queue
capacity does not prove a frame-time, filesystem-latency or throughput guarantee.
No disk operation holds the queue mutex; status and poll only synchronize queue
state. `stats()` reports current reservations/counts, high-water marks and lifetime
accepted/finished/admission-rejection/worker-start counts. Basic invalid-argument
rejections are not included in `backpressure_rejections`.

## Unload acknowledgement and lifecycle

Keep the exact captured packet until its successful publish completion arrives.
Only then call `blocks.unload_region(packet)` on the scene thread. If editing
changed that region while I/O was pending, unload rejects the old capture: retain
the live cells and publish the new version. A successful read returns `bytes` for
the normal region restore API; restore can still reject unavailable capacity or
an unexpected version. The queue does not weaken either transfer check.

`request_stop()` closes admission immediately and wakes the worker to drain all
accepted work. It does not wait for disk. Poll while stopping, then observe
`stats().running == false`. Completed results remain available after shutdown.
`join()` requests stop and blocks until draining and lease release finish;
destruction does the same. Use this blocking path at an explicit lifecycle boundary,
not in a gameplay frame. There is no cancellation of accepted writes or deadline
for stalled filesystem calls. Restart is allowed only after the worker has stopped
and all completions have been consumed. The destructor may discard unread results
after work finishes, so explicitly consume failures before orderly application exit.

## Validation

All 89 checks pass using real local files with debug and clean release DLLs. It exercises
FIFO ordering across failed conditional writes, caller packet/container mutation,
count/byte saturation while results remain unread, bounded polls, failed open and
restart, retained results during shutdown, 20 destructor-with-write cycles, an
edited-after-capture unload rejection, and exact unload/read/restore. Another 100
committed revisions with dependent reads reuse one worker and release reservations
after each cycle. See `docs/evidence/block_region_io` for reports and build hashes.

These are correctness/lifecycle tests, not large-city travel, OS power-interruption,
multi-hour endurance or full-capacity throughput measurements. The demo has not
been switched to automatic authored-region eviction. A paging manager, world-root
transactions and model-region storage remain necessary for the requested world.
