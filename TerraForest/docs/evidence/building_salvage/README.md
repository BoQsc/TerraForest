# Building salvage gameplay

Normal world, temporary save, fullscreen 1920x1080. Actual shared ray targeting
and attack entry point hit an open door, window and guardrail. Initial hits
preserve the model; repeated attacks remove it, wear the hatchet, and recover
exactly 3 wood / 2 wood / 2 metal respectively. Repeat removal grants nothing.
Protected parts reject damage without inventory/wear changes; a protected open
door keeps its hinge record. Successful destruction clears the hinge record.

Recipes use the existing native salvage transaction, below their placement cost.
No new per-frame work. Tool cooldown is reset between test attacks to keep the
fixture short. This does not measure frame performance or prove disk reload;
the temporary-world shutdown explicitly skips saving. Windows still break as
whole objects, with no separately collectible glass.

Command: `python tools/run_godot_check.py building_salvage --timeout 65 --require "COMBINED_RESOURCE_ROUTE failures=0"`.
