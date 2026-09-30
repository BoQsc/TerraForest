This directory preserves the measured pre-compaction probe, including its
instrumentation. report.json contains the original relative source paths and
SHA-256 values. The three modified probe files are copied here byte-for-byte.
Other native files were unchanged from commit 31b665c.

To reproduce, use an isolated checkout of 31b665c, replace the two native probe
files and tools/probe_terrain_incremental_dual.py with these snapshots, and run
the Python probe. Do not overwrite an active development checkout.

The snapshots contain project-authored 0BSD code. There are no Transvoxel tables.
