# Finite quantity contract

2026-10-11. 20 focused checks pass in the native debug addon and a clean project
loading only the release water addon. Each includes 20,000 deterministic transfers
against an independent integer oracle, exact conservation, partial pours, rejected
scoops, replay rejection, deletion protection, persistence/corruption/forged total,
record cap and aggregate overflow. The existing shoreline regression also passes
with the rebuilt addon. Full command and binary fingerprints are retained.

The 4096-record snapshot is exactly 98,352 bytes. Transaction test timings include
GDScript oracle bookkeeping and API allocation/dispatch; they do not measure a
fluid solver or establish a game-frame budget. The class owns no process loop.

This is an implemented accounting prerequisite, not dynamic water or bucket
 gameplay. No fluid geometry, world-save migration or inventory state was changed.
Remaining requirements: ../../FINITE_WATER.md.
