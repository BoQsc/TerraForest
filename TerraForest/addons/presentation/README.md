# Presentation policy

Low-frequency Godot presentation support for a fixed **1920×1080** render viewport, 100% 3D render scale, and a saved fullscreen/windowed choice. The operating system may present that viewport on a display with different native dimensions; the actual window and render dimensions are recorded separately.

`WorldSession` applies `fullscreen_policy.gd` before the initial scene, after scene changes and on focus return. F11 toggles the preference in the browser, generation/loading screens, gameplay and dialogs. Graphics settings persist independently of whether world edits are temporary. Session-only policy callers retain their choice across reapplication without writing the configuration file. Already-windowed stages preserve their size and position; minimized windows remain minimized on automatic reapplication. Windows' decorated maximized fallback is retained for the engine transition anomaly.

The project opens its boot splash in a decorated 1280×720 window, then applies the saved preference. The browser and normal launchers do not force fullscreen before scripts run. World/photograph and external generation commands inherit the selected mode. Offscreen generation and photographs use SubViewports, never additional native windows. Fullscreen remains the default when there is no preference. The graphical soak test requires fullscreen 1080p at full scale for comparable measurements; windowed/headless correctness tests are not FPS evidence.

The shared policy requests VSync after changing window mode. The main controller reapplies VSync when focus returns. Project settings explicitly enable VSync before scripts start, and the standalone structures demo uses the same policy. This uses Godot's normal presentation, with no custom swap chain. Borderless fullscreen replaces exclusive fullscreen as a mitigation for reported tearing; Windows/driver presentation behavior still needs visual confirmation on the affected display. The HUD reports the requested mode, not proof of tear-free physical scanout. A frame-rate cap is separate from synchronization.

`tests/presentation.gd` checks the fullscreen render dimensions and enabled VSync after restoring a deliberately disabled mode, and records the GPU, renderer and display refresh rate. Screenshots and engine getters cannot establish absence of monitor tearing. See `docs/VSYNC_PRESENTATION.md` for the validation scope.

`tests/window_modes.gd` checks repeated toggles and idempotence. `tests/windowed_stages.gd` observes every frame across browser, generation/cancellation, resource loading, gameplay, embedded dialogs, save/return and reopening; it also exercises F11, Graphics and focus recovery on the same native handle. It uses a disposable graphics file and worlds, and disables derived caching to isolate presentation from the existing cache-directory API error.

Historical 1600×900 results remain historical; they must not be presented as 1080p comparisons.
