# Offline credits and notices

The world browser's **Credits & licenses** button opens a searchable, scrollable
viewer. **Back** and **Escape** return keyboard focus to the button. The footer
stays available while the world-browser workspace scrolls on smaller displays.

`notices.json` contains ten project, asset and dependency notices copied from
their retained source files, with short explanations of their scope. Rebuild it
after changing a source notice:

```text
python tools/build_credit_notices.py
python tools/build_credit_notices.py --check
```

The pack exporter runs the freshness check. The export preset explicitly includes
the JSON so full project notices remain readable offline in an exported build.
Godot's own license, component copyrights and license texts come directly from
the running engine, independently of the bundled project notices.

Inherited terrain textures retain their existing provenance note. This feature
does not establish new reuse rights for those textures or change component terms.

## Verification

`tests/credits_licenses.gd` exercises the actual browser button, retained notices,
search, scroll access, Back/Escape focus return, repeated opening and layout at
1920 x 1080 and 1280 x 720. Screenshots and the passing log are retained under
`reports/credits_licenses/`, outside Godot imports and exports.

A minimal export fixture using the production dialog, notice bundle and export
preset was imported, exported to PCK and run from a folder containing only that
PCK. All 132 entries supplied by Godot 4.7.2 and the project bundle were readable.
This checks credits packaging, not a full-game release export.

The wider `tests/world_browser.gd` run remains failing: its generation assertions
expect older identities (including 23 instead of the current 29), and its fixed
three-parent lookup expects a TabContainer where the unchanged browser has a
VBoxContainer. The baseline probe confirmed these mismatches without the credits
changes. Retained evidence:
`reports/checks/20261030T082540084239Z/console.log` and
`reports/credits_licenses/baseline_probe.log`. Synchronizing that regression with
the current launch contract and control hierarchy remains separate work; then
rerun it and require `WORLD_BROWSER failures=0`.
