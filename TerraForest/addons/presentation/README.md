# Presentation policy

Low-frequency Godot startup support for a fixed **1920×1080** render viewport, 100% 3D render scale, and exclusive fullscreen (or the engine's supported fullscreen mode). The operating system may present that viewport on a display with different native dimensions; the actual window and render dimensions are recorded separately.

`fullscreen_policy.gd` is applied by the demo controller at startup. F11 reapplies fullscreen instead of allowing benchmark resolution changes. The graphical soak test rejects measurements unless the render viewport, fullscreen state and render scale match this policy. Headless correctness tests remain headless and are not FPS evidence.

Historical 1600×900 results remain historical; they must not be presented as 1080p comparisons.
