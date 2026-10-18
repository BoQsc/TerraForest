# Docked construction visibility and notice timing - 2026-10-18

Each world notice called construction_palette.synchronize, which made the active construction panel visible; session_menu.sync_panels immediately hid it outside the editor workspace. Visibility is now controlled only by the session menu after docking. Standalone palette users retain the old default through an optional manage_visibility argument. The graphical population fixture observes visibility_changed and verifies zero toggles during placement notices.

Named timing now separates notice panel synchronization from message output. Before the fix, panel-sync maxima were 5.415/5.362 ms for 4/64 cottages. Afterward they were 0.784/0.070 ms. These are individual observations on a variable workload, not a sustained speedup guarantee. The behavioral invariant (no docked-panel visibility toggles) passes.

The unchanged 4 ms placement-call gate still FAILS for 64 cottages: maximum update 5.819 ms, of which message output was 4.479 ms, native transaction 0.941 ms, inventory-refresh revision check 0.077 ms. Four-cottage input/update were 3.178/2.482 ms. No claim that the earlier intermittent 138 ms event has been fully resolved. Message output includes the ordinary controller status-label update and synchronous console print; split these before deciding any logging policy change.

Same measurement limits as direct_prefab_world_cost: normal controller processing disabled, explicit calls, child terrain/render processing active, elevated disposable fixtures, no full gameplay/frame/thermal qualification. Block counts and zero panel-toggle assertion pass. Water and human saves unchanged.
