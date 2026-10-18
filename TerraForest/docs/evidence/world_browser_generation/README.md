# Integrated browser generation

Worlds.cmd now defaults to an integrated regional preset. Create and play starts the
existing verified Python preparation pipeline, waits for atomic completion status,
and opens only the published save. The browser uses a 10 FPS cap while waiting.
Repeated launch clicks are ignored; failures keep the browser with a reason/log path.
Opening existing saves retains their generation settings and chosen gameplay mode.

Actual UI creation produced browser_seed50_137350, including the mixed-layout correction
(world seed 50, building-layout seed 51). Bake and fresh-process reopen passed; the
browser then launched the real gameplay process with the published slot. The first
harness expected to intercept that launch but its hook had not been installed, so
its marker failed; the launched test game was closed by its verified process ID.
The corrected completion hook was tested against that same successful job, without
regenerating: success launches the expected arguments, failed status does not launch,
and repeated Create does not start another process. Graphical browser layout checked
at 1920x1080. Ten Python preparation tests pass including failed/exception status.

This is the local development workflow, requiring Python on PATH. Standalone/export
packaging, job cancellation and richer progress reporting remain unfinished.
