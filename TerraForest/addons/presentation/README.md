# Presentation policy

Low-frequency Godot startup support for a fixed **1920×1080** render viewport, 100% 3D render scale, and borderless fullscreen. The operating system may present that viewport on a display with different native dimensions; the actual window and render dimensions are recorded separately.

`fullscreen_policy.gd` is applied by the demo controller at startup. F11 reapplies fullscreen instead of allowing benchmark resolution changes. The graphical soak test rejects measurements unless the render viewport, fullscreen state and render scale match this policy. Headless correctness tests remain headless and are not FPS evidence.

The shared policy requests VSync after changing window mode. The main controller reapplies VSync when focus returns. Project settings explicitly enable VSync before scripts start, and the standalone structures demo uses the same policy. This uses Godot's normal presentation, with no custom swap chain. Borderless fullscreen replaces exclusive fullscreen as a mitigation for reported tearing; Windows/driver presentation behavior still needs visual confirmation on the affected display. The HUD reports the requested mode, not proof of tear-free physical scanout. A frame-rate cap is separate from synchronization.

`tests/presentation.gd` checks the fullscreen render dimensions and enabled VSync after restoring a deliberately disabled mode, and records the GPU, renderer and display refresh rate. Screenshots and engine getters cannot establish absence of monitor tearing. See `docs/VSYNC_PRESENTATION.md` for the validation scope.

Historical 1600×900 results remain historical; they must not be presented as 1080p comparisons.
