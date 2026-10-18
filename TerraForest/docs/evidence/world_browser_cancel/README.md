# World preparation cancellation — 2026-10-18

Worlds.cmd now displays Cancel preparation while its owned preparation runs.
The browser writes a uniquely named request file. Python polls it at up to 0.2s
intervals while waiting on its own Popen child; cancellation kills and reaps that
child only. Preparation releases its destination lock in finally and reports
cancelled. Staging artifacts/logs remain for diagnosis; no existing saves are
removed. Browser restores60FPS and does not open gameplay after cancellation.
Quit/window-close requests use the same cancellation path and wait for completion.

Cancellation checks precede each phase and publication. Publication itself is not
interrupted: a late cancellation can leave a fully verified saved world, and the
browser explicitly reports that outcome without launching it. No incomplete world
is published as a consequence of cancellation.

15 Python preparation tests pass, including pre-start cancellation, a request at
the publication boundary, existing-save protection, failure handling and killing/
reaping a real sleeping child process. Actual graphical browser test starts the
real preparation pipeline for a unique seed42slot, waits forcreating, then presses
the actual cancel button after3seconds. Stopobserved814ms; cancelledstatus, no
destination.trw, no preparation lock, no gameplay launch and restoredbrowser60FPS.
Screenshot inspected. No Godot process remained after the test. This does not test
cancellation at every native generation step or during arbitrary OS failure.
Standalone preparation packaging and finer location progress remain open.
