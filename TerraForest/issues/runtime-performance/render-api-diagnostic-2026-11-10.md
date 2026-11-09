# Rendering API diagnostic; production remains Vulkan

Status: preliminary diagnostic only, no production renderer/configuration change.
Approved foreground/background caps, VSync and Forward+ quality remain intact.

The animation-cache correction still leaves low-main-thread-work rendering stalls,
including 39.013 ms drawing in a 49.358 ms source frame. Windows WPR CPU recording
fails with `0xc5585011`; no system profiling policy was changed. A bounded
command-line graphics-API comparison is another way to investigate the renderer
boundary without reducing geometry, shadows, materials, resolution or gameplay.
Godot supports both APIs with Forward+ ([official rendering overview](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html)).

The test launcher now accepts an explicit diagnostic driver and records the
actual runtime driver/method. It fails a requested-driver mismatch rather than
silently accepting a fallback. This flag is not added to normal launch commands.

`reports/performance_changes/20261109T222504020556Z_d3d12_wait_diagnostic` reports
actual `d3d12` / `forward_plus`, cap 60 and VSync enabled. Grounded walking,
three-barrel destruction, HUD checks and save/shutdown pass without error/leak
diagnostics. Outdoor p99/max is 22.595/23.843 ms; recovery 18.951/20.123 ms.
Peak private commit reaches 4.41 GiB, above the provisional warning band.

The nearby installed Vulkan walking capture has outdoor p99/max 20.402/25.243 ms
and recovery 19.407/21.869 ms. These are not an interleaved, thermally matched
backend comparison. The D3D12 run uses the source engine and a first-use shader
cache; no isolated driver-performance gain or universal visual parity is claimed.
There is not enough evidence to adopt a different backend. Production remains
Vulkan. Rare-wait attribution, recorder overhead and endurance remain open.
