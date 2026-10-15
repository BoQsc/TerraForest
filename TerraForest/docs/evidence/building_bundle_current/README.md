# Current building dependency bundle — 2026-10-16

The structures ZIP imports and loads 104 resources in a new, cache-free Godot 4.7.2 Windows project. All 99 graphical interaction assertions pass at fullscreen 1920x1080 capped at 60 FPS. Archive SHA256 and fixture SHA256 are recorded in result.json; dependency closure is in ADDON_PACKAGE.json. This is a dependency bundle, not a promise that every adapter runs without its host-world contract.

Coverage includes seven native shapes/four rotations, actual collision matching authored picking, preview meshes, prefab capture/rotated placement/snapshot restore, window/fence/guardrail removal and restoration, sheared stair rails with space below the bar, and door open/close persistence. Files resolve only from the extracted ZIP. Both native DLL targets are included; runtime exercise uses the debug DLL.

The six Python packaging contract tests also pass. They exposed a real missing dependency: session_menu.gd hard-coded demo/worlds.tscn. The addon now has an optional host-configured world_browser_path; the main demo supplies its scene. Unconfigured/missing destinations return before save/shutdown, and the browser button is omitted when unconfigured. Existing safe-save failure checks pass. The actual main-world create/save/browser-return/fresh-reopen route passes after this change, using a new disposable slot.

Retained rejected_overlap logs show a fixture problem: block samples overlapped later window/rail removal rays. Restoring the empty block fixture before model checks fixes the overlap without changing production collision.

Limits: no exported executable, Linux/macOS, release-runtime, dense-city performance, thermal, endurance or multiplayer qualification. No water behavior changed. The archive is local under dist/structures.zip; it has not been published as a GitHub release.
