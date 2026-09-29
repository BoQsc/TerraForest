# Authored block-region transfers

`NativeBlockWorld` can now transfer authored data independently of mesh residency. A region is 64×64×64 local cells, containing at most 4×4×4 existing 16-cell chunks. Region coordinates use mathematical floor division, including negative coordinates. Their valid range is -16,384 through 16,383 per axis, within the existing cell-coordinate limits.

This is an explicit native transfer API. The demo does not automatically unload authored regions during travel yet. A durable region catalog, crash-safe file transactions, background disk I/O, automatic admission/eviction, cross-region editing history and model-region storage remain required for complete large-world paging. Whole-world saves are deliberately unavailable while any region has been explicitly unloaded; existing single-file saves cannot represent that state safely.

## API and ownership

- `capture_region(region)` returns a canonical checksummed packet or empty bytes for invalid/unavailable regions. It performs 64 chunk lookups and encodes at most 64 chunks; it does not encode the entire world.
- `validate_region_snapshot(bytes)` checks the envelope, length, checksums, chunk count, existing block encoding and region membership without mutating the world.
- `unload_region(expected_snapshot)` accepts only an exact current capture. An edit in that region after capture causes rejection; edits elsewhere do not. The caller must first successfully persist and verify the packet. The method cannot itself prove that bytes reached durable storage.
- `restore_region(bytes, expected_current)` validates the complete packet and final resident capacity before mutation. For a resident region, `expected_current` must match its current capture. For a previously unloaded region, it must be empty and the incoming packet must match the checksum recorded at unload. This prevents loading an older or unrelated version into that unavailable region.
- `is_region_loaded(region)` distinguishes unavailable regions from known empty space. `get_cell()` alone still returns zero for absent resident data and must not be used as an availability check.
- `region_stats()` reports resident chunks, unavailable-region count, retained digest bytes, metadata capacity and whole-snapshot availability.

Capture and mutation belong on the scene owner thread. An I/O worker can persist immutable packet bytes and return its result to that thread; stale acknowledgements are rejected by `unload_region`. A rejected command leaves authored data, region availability and history unchanged. Successful transfers clear undo/redo as a history barrier. An explicit valid `restore_snapshot` replaces the entire block world and resets region-transfer state.

Unloaded regions retain one 32-byte checksum plus container metadata, not their authored cell arrays. Metadata is capped at 65,536 unavailable regions. Resident storage remains capped at 2,048 chunks. Packet validation is capped at 2 MiB; an empty region is a valid 100-byte packet. Encoding may temporarily copy up to 64 chunks. Main-thread encode/validate/apply operations are bounded by these counts, but do not have a measured hard time budget. Derived mesh/physics retirement still follows the existing pipeline and is not guaranteed to finish in the unload call.

## Missing data and safety

An unavailable region blocks walking readiness even when no resident cells remain. Direct edits, prefab placement and prefab capture cannot treat its missing cells as air. Vegetation exclusion conservatively reserves the whole unavailable region. Region replacement invalidates face-neighbor bake dependencies and outstanding tickets, so cross-region seams regenerate and stale worker results cannot republish unloaded geometry.

`capture_snapshot()` returns empty bytes while any region is unavailable. The compound structure codec rejects that result, preventing the existing world-save component from silently writing a resident-only building snapshot. Callers must handle that failure, reload every region, or use a future catalog-aware save format. SHA-256 provides content integrity and version matching; it is not multiplayer authorization or proof of durable disk writes.

## Packet format

`TFRG` version 1 uses an eight-byte magic/version header, three little-endian signed 32-bit region coordinates, a 32-bit payload length, a canonical `TFBL` block snapshot payload, then a 32-byte SHA-256 digest of the preceding bytes. The nested block snapshot retains its own version/checksum and RLE validation. Every chunk must belong to the envelope's region, and at most 64 chunks are accepted. A correctly recomputed checksum does not bypass spatial or semantic validation.

## Validation

All 43 region checks pass with both debug and clean release DLLs. They include a real file round trip, stale capture rejection, wrong-version reload rejection, malformed envelopes, signed boundaries, capacity overflow, empty regions, transformed readiness, compound save rejection, forty eviction/reload cycles, neighbor seam rebuilding and an observed outstanding bake at unload. The existing 281 native structure checks also pass. The integrated 1920×1080 fullscreen world passes 167 checks, including standing-player wait/resume and save availability across an authored-region transfer.

Reports and native build fingerprints are retained in `docs/evidence/block_regions`. These correctness tests do not establish multi-hour endurance, crash recovery, automatic travel paging or large-city frame-time guarantees. Both Windows extensions link the pinned prebuilt Godot SDK with Zig 0.16; no godot-cpp sources were compiled.
