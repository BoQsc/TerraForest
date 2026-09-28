# Fullscreen presentation and reported tearing

The user reported horizontal splits while turning or moving. This is consistent with tearing, but physical scanout was not captured and the root cause is not established.

Inspection found the main controller already requested `VSYNC_ENABLED`. The shared fullscreen policy only changed the window mode, the standalone building scene did not use that policy, and startup also promoted borderless fullscreen to exclusive fullscreen. No custom swap chain or split-screen compositor was found in those presentation paths. Some explicitly uncapped performance tests deliberately disable synchronization; normal gameplay does not.

The project now explicitly requests VSync in project settings. Normal gameplay and the standalone building scene use the shared 1920×1080, full-scale borderless fullscreen policy, with VSync requested after the window transition. The main controller restores VSync on focus gain; F11 reapplies the policy. There is no per-frame synchronization setter. Existing 60 FPS foreground cap remains a separate power/headroom setting. The HUD says “V-Sync requested” because an engine getter cannot prove what the physical display shows.

Graphical presentation validation on this machine reported Godot 4.7.2, Vulkan Forward+, NVIDIA GTX 1060 Max-Q, fullscreen mode 3, VSync mode 1, 1920×1080 viewport/window/captured image and approximately 60.02 Hz display refresh. It also deliberately disabled VSync and verified policy recovery. This proves engine configuration and render dimensions, not absence of tearing on scanout. Borderless mode is a mitigation that still needs the user's motion check after restarting the world.

If tearing remains, collect whether the application is the source world or an older exported executable and whether the HUD requests VSync. Check the driver application profile for forced-off VSync before changing rendering or terrain code. No driver settings were changed by this patch. Driver settings and Windows fullscreen optimizations can affect presentation independently of the requested engine mode.

Godot's API semantics: https://docs.godotengine.org/en/stable/classes/class_displayserver.html#enum-displayserver-vsyncmode
