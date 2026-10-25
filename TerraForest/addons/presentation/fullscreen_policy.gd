extends RefCounted
## Startup/UI policy only. No simulation work or per-frame loop.
const RESOLUTION := Vector2i(1920, 1080)
static func settings_path()->String:return ProjectSettings.get_setting("terraforest/graphics_settings_path","user://graphics.cfg")

static func apply(window: Window) -> void:
	window.content_scale_size = RESOLUTION
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.scaling_3d_scale = 1.0
	if DisplayServer.get_name() != "headless":
		# Use Windows' composed fullscreen path, including on hybrid-GPU laptops.
		# Apply synchronization AFTER the window transition recreates presentation.
		var settings:=ConfigFile.new()
		var fullscreen:=true
		if not settings_path().is_empty() and settings.load(settings_path())==OK:fullscreen=bool(settings.get_value("graphics","fullscreen",true))
		set_fullscreen(window,fullscreen,false)
		restore_vsync()

static func set_fullscreen(window:Window,enabled:bool,persist:bool=true)->void:
	if DisplayServer.get_name()=="headless":return
	var mode:=DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode()!=mode and (enabled or DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_MAXIMIZED):
		window.mode=Window.MODE_FULLSCREEN if enabled else Window.MODE_WINDOWED
		if not enabled:
			window.borderless=false
			if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
				window.mode=Window.MODE_MAXIMIZED
			var usable:=DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_WINDOWED:
				window.size=Vector2i(mini(1280,usable.size.x-80),mini(720,usable.size.y-80))
				window.position=usable.position+(usable.size-window.size)/2
	restore_vsync()
	if persist and not settings_path().is_empty():
		var settings:=ConfigFile.new();settings.load(settings_path())
		settings.set_value("graphics","fullscreen",enabled);settings.save(settings_path())

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

static func refresh_frame_cap(active_cap: int,background_cap: int) -> void:
	# Embedded GUI focus is not OS application focus. A focused native dialog
	# also belongs to the application. Call after focus signals have settled.
	var focused:=DisplayServer.get_name()=="headless"
	if not focused:
		for id: int in DisplayServer.get_window_list():
			if DisplayServer.window_get_mode(id)!=DisplayServer.WINDOW_MODE_MINIMIZED and DisplayServer.window_is_focused(id):
				focused=true;break
	Engine.max_fps=active_cap if focused else background_cap
