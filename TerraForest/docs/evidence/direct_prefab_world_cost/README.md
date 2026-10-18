# Direct furnished placement cost in the world - 2026-10-18

New short graphical fixture measures ordinary editor input and incremental world placement calls for 4 and 64 furnished cottages (1,896/30,336 cells; 12/192 model attachments). Native preparation/publication and completion feedback now emit named timing stages. The main world controller process and physics are disabled during explicit measured calls, while child terrain/renderer processing continues. These are call-cost measurements in a world scene, not normal gameplay frame-time qualification or natural terrain siting. Placement is elevated. Post-draw intervals are retained as observations only.

The 4 ms per-call gate FAILS. Before optimization, inventory refresh within completion feedback took 30.871 ms at 4 cottages and 11.763 ms at 64. The free-editor transaction had not changed inventory. Completion now refreshes item presentation/recipes only if inventory revision differs from the displayed revision. Paid publication still changes revision and follows the existing refresh path.

Afterward, the inventory stage measured 0.074/0.124 ms. Four-cottage input/update were 3.077/1.871 ms. The 64-cottage input was 1.993 ms, but maximum update was 141.559 ms: completion notification accounted for 138.029 ms, while native transaction maximum was 1.138 ms. That remaining intermittent notification/UI cost is unresolved. Do not claim placement latency is fixed, or infer a general speedup from these single samples. Native block/model validation timing fields are cumulative preparation totals, unlike per-call transaction maxima.

Fixture corrections: initial reference capture counted the aiming block; the final assertion compares total cell delta against the authored population. Early manual calls also overlapped automatic controller updates; final measurement explicitly disables that controller. Prior console logs remain in reports/checks. before.json and after.json use the corrected measurement setup and retain failures.

Next investigation: split completion notification into panel synchronization, notice composition and message output before changing behavior. Preserve the unchanged 4 ms gate. No water changes or human-save edits.

Reproduce: python tools/run_godot_check.py direct_prefab_cost --timeout 65 --require 'DIRECT_PREFAB_COST failures=0'. Failure is currently expected and must remain visible.
