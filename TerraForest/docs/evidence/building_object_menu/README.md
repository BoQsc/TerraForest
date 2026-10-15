# Object chooser

The normal-world developer Objects page was checked at fullscreen 1920x1080.
The panel fits; all eleven catalog buttons can be brought wholly into the
scroll viewport. Emitting each button's pressed signal selects its matching
model. Returning to the world retains the active final selection.

The inspected screenshot shows the two-column layout with 64-pixel icons and
80-pixel rows. Full titles and material costs are available in tooltips.
This test uses button signals, not OS mouse automation. It does not place
objects, qualify performance, or prove human acceptance. Temporary-world save
is skipped; the inherited save-completes label is not persistence evidence.

Command: `python tools/run_godot_check.py building_object_menu --timeout 65 --require "COMBINED_RESOURCE_ROUTE failures=0"`.
