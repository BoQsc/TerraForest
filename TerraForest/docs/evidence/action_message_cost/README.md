# Routine action feedback without synchronous console mirroring - 2026-10-18

Split message timing identified console output as the dominant notice cost: at 64 cottages console max2.202 ms versus label max0.006 ms in the baseline sample. Routine _show_lake_notice actions now update the same status/telemetry and retain the latest64 strings in world.recent_action_messages without printing by default. Use --log-actions (world.log_action_messages) for console mirroring. ERROR-prefixed action notices still print; ordinary _message callers, including world save/load status, retain logging. Engine errors/warnings are unaffected. This is explicit logging policy, not deferred output that would block a later frame.

Both post-change short fixtures pass the unchanged4 ms per-call gate. First 64-cottage input/update maxima0.598/2.895 ms; final0.594/1.215 ms. Four-cottage final0.387/0.603 ms. These are two bounded samples, not sustained-frame or thermal qualification. Existing failures remain in prior evidence. The entire earlier138 ms transient is not proven explained by this one component.

Final regression checks all authored blocks, docked-panel stability, unchanged visible action feedback, latest64 retention after70 messages and opt-in console output (ACTION_CONSOLE_OPT_IN appears in final.log). Earlier native preparation/cancellation and paid persistence evidence remains applicable; no world-storage or native-transaction changes here.

Measurement scope remains explicit: graphical main world with controller processing disabled, manually advanced placement, child terrain/render processing active, elevated disposable4/64-cottage fixtures. Inputs, preparation updates and final completion are measured; post-draw intervals are observations, not full gameplay measurements. Water and human saves unchanged.

Reproduce: python tools/run_godot_check.py direct_prefab_cost --timeout65 --require 'DIRECT_PREFAB_COST failures=0' (use --timeout 65 as separate arguments). Log mirroring can increase call latency and is intended for diagnostics. Recent messages are accessible to diagnostics/scripts; no new history window is introduced.

Disposition: stop this focused attribution pass and resume broader world coverage. Detailed populated-world rendering, sustained placement/editing, dense actors and old-laptop thermal gates remain open.
