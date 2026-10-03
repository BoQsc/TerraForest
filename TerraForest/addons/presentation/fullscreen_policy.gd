extends RefCounted
## Startup/UI policy only. No simulation work or per-frame loop.
const RESOLUTION := Vector2i(1920, 1080)

static func apply(window: Window) -> void:
	window.content_scale_size = RESOLUTION
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.scaling_3d_scale = 1.0
	if DisplayServer.get_name() != "headless":
		# Use Windows' composed fullscreen path, including on hybrid-GPU laptops.
		# Apply synchronization AFTER the window transition recreates presentation.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		restore_vsync()

static func restore_vsync() -> void:
	# Focus returns from embedded dialogs too. Reapplying an unchanged mode can
	# stall presentation; only request a mode change when synchronization is off.
	if DisplayServer.get_name() != "headless" and DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_ENABLED:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

static func measurement(window: Window) -> Dictionary:
	var viewport: Vector2i = Vector2i(window.get_visible_rect().size)
	var mode: int = DisplayServer.window_get_mode()
	var fullscreen: bool = mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	return {"viewport": [viewport.x, viewport.y], "window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y], "fullscreen": fullscreen, "window_mode": mode, "render_scale": window.scaling_3d_scale, "headless": DisplayServer.get_name() == "headless", "fair_graphical_sample": viewport == RESOLUTION and fullscreen and is_equal_approx(window.scaling_3d_scale, 1.0)}
