# Alt-Tab input recovery

2026-10-24. Pressing Alt gives temporary cursor access to tool controls. On
application focus loss, the existing code cleared that access flag and dismissed
tool popups but left the cursor visible. If Alt was released in another application,
its key-up could not restore capture, so returning left gameplay without mouse
look/movement until another UI action changed capture. Separately, the inventory
shortcut accepted Tab with Alt held, allowing window switching to open inventory.

The tool HUD now retains a pending cursor return when focus loss ends temporary
Alt access. It restores capture after focus notifications settle, provided the
main game is focused and no loading/shutdown/inventory/storage/session/tool/map
interface owns input. Root-window focus also completes a pending return after a
native child dialog. The signal uses a bound, deferred callable, so scene teardown
disconnects it. This adds no polling. Existing intentional menus remain open and
keep a visible cursor. Movement/strokes still cancel on focus loss.

Inventory ignores Alt-Tab with either the event's Alt modifier or the physical
Alt state set, including Shift-Alt-Tab. Meta-Tab is excluded too. Plain Tab retains
its original inventory action. The old development test expectation that Alt-Tab
opens inventory was corrected to match the user's requested behavior.

The `focus_return` check uses the actual playable scene, injected keys/mouse and
explicit application/window focus notifications. Its 29 assertions cover both
focus event orders, Alt key-up missing until after return, immediate movement and
mouse look, tool popup dismissal, preserving four genuine modal interfaces, and
waiting for root-window focus after app focus. These are scene integration checks;
the fixture does not automate the Windows desktop task switcher.

All **93 assertions** pass across the final runs:

| Record | UTC run ID | Assertions |
| --- | --- | ---: |
| [Source focus recovery](source/console.log) | `20261024T100618291927Z` | 29 |
| [Development controls](development/console.log) | `20261024T100954413536Z` | 35 |
| [Packaged focus recovery](packaged/console.log) | `20261024T101245102556Z_focus_return_pack` | 29 |

Export and startup pass with fourteen external native libraries. The updated game
scripts and exported package are installed locally. No native library changes
or save-format changes are required.

The development-belt regression also covers the regular Alt controls, detailed
settings, movement, mode changes and inventory. Its first run retained unrelated
stale expectations: it omitted the existing Developer spawner page and treated
the repair hammer as the building tool. The fixture now selects owned brick for
building and expects the existing global Developer page; runtime behavior was not
changed to accommodate those assertions. The failing record is preserved.

Reproduce:

```powershell
python tools/run_godot_check.py focus_return --timeout 100 --require 'failures=0' -- --gameplay-construction --no-zombies
python tools/run_godot_check.py developer_belt --timeout 110 --require 'failures=0' -- --gameplay-construction --no-zombies
python tools/export_pack.py --godot 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\Godot Engine.exe'
python docs/evidence/focus_return/check_pack.py
```

Run the last command only after export finishes. Its assertion driver is external;
the actual game UI/scripts/assets and native libraries resolve from PCK/dist.
The manifest includes the driver, engine, package and native-library hashes.
