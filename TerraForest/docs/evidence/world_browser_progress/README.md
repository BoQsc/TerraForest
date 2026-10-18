# World preparation progress — 2026-10-18

The preparation process atomically reports creating/verifying/publishing immediately
before the corresponding real operation. Final ready/failed state remains owned by
the existing completion path. Browser polling reads stage while the owned process
is alive, displays elapsed time, and still waits for exit plus ready status before
launching gameplay. No speculative percentage or estimated finish time is shown.

12 Python preparation tests pass, including operation-order progress callbacks,
creation failure suppressing later stages/publication, reopen failure, duplicate
preparation and existing-save preservation. The graphical browser test passes with
controlled status files and its own live PID as the sentinel. Screenshot inspected
at1920x1080. This verifies UI polling and labels, not a new full-world bake; the
previous integrated preparation/reopen evidence remains separate.

World generation cancellation, packaged Python-independent preparation, finer
per-location progress and broader world-quality acceptance remain unfinished.
