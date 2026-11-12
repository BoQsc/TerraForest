# SPDX-License-Identifier: 0BSD
extends Node
## The hub's permanent taskbar-notification-area presence.
##
## Added by the hub scene (`worlds.gd`) and kept by `WorldSession`, so the tray
## icon survives world load/unload and is the way back to the hub browser.
##
## Closing the window hides the game behind its notification-area icon: the
## window is minimized (Godot has no hide-window API on Windows) and the icon
## becomes the only control, until it is pressed. The hub's own Quit button is
## unchanged; the tray menu also offers "Quit TerraForest". Worlds keep their
## own close behaviour so leaving a world still returns to the hub. On display
## servers without status indicators (headless, Linux) nothing changes.
const HUB_SCENE:="res://demo/worlds.tscn"
## PNG on purpose: Godot has no .ico loader and the tray needs a Texture2D.
const ICON_PATH:="res://addons/hub/tray_icon.png"
const TRAY_SIZE:=32
signal mode_changed(minimized:bool)
var supported:=false
var minimized:=false
var _close_armed:=false
var tray:StatusIndicator
var _menu:PopupMenu
## The single process-wide tray owner (see `ensure`).
static var _instance:Node
func _ready()->void:
	supported=DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR) and not Engine.is_embedded_in_editor()
	if not supported:return
	# One frame later: StatusIndicator registers with Windows on entering the
	# tree, and doing that before the main window exists means no icon at all.
	_create_tray.call_deferred()
func _create_tray()->void:
	if not is_inside_tree() or tray!=null:return
	tray=StatusIndicator.new()
	tray.name="Tray"
	tray.tooltip="TerraForest hub"
	tray.icon=tray_texture()
	tray.visible=true
	add_child(tray)
	_menu=PopupMenu.new()
	_menu.name="TrayMenu"
	_menu.add_item("Show hub",0)
	_menu.add_item("Quit TerraForest",1)
	_menu.id_pressed.connect(_menu_action)
	add_child(_menu)
	# Set right after entering the tree: the setter resolves this path at once,
	# so it cannot be assigned before the indicator is inside the tree.
	tray.menu=_menu.get_path()
	tray.pressed.connect(_on_tray_pressed)
	# Arm only once the hub window has been shown; a later close then means
	# "to the tray". Worlds re-arm on their own notifications, so their close
	# requests never reach this handler.
	hub_shown.call_deferred()
## Left click raises the hub; right click belongs to the native menu.
func _on_tray_pressed(button:int, position:Vector2i)->void:
	if button==MOUSE_BUTTON_RIGHT:
		# Do nothing at all. Godot/Windows opens `tray.menu` for the right
		# button; popping it ourselves made it an embedded subwindow, which
		# forced the minimized game window back up over the menu.
		return
	show_hub()
func supported_here()->bool:
	return supported
## True when a close request should go to the tray instead of quitting.
func handles_close()->bool:
	return supported and _close_armed
## Square, exactly TRAY_SIZE pixels: Windows crops anything else.
func tray_texture()->Texture2D:
	if not ResourceLoader.exists(ICON_PATH):return null
	var source:=load(ICON_PATH) as Texture2D
	if source==null:return null
	var image:=source.get_image()
	if image==null:return source
	image.resize(TRAY_SIZE,TRAY_SIZE,Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)
## Called by the hub scene every time it becomes current.
func hub_shown()->void:
	_tray_visible(true)
	minimized=false
	_close_armed=true
	mode_changed.emit(false)
func world_active()->void:
	_tray_visible(true)
	_close_armed=false
## Worlds are created by WorldSession, after the hub scene is gone; they call
## this so the icon is not destroyed together with the hub browser.
static func ensure(tree:SceneTree)->Node:
	if is_instance_valid(_instance):return _instance
	var existing:=tree.root.get_node_or_null("HubWindow")
	if existing!=null:
		_instance=existing
		return existing
	var owner:Node=load("res://addons/hub/hub_window.gd").new()
	owner.name="HubWindow"
	_instance=owner
	# Deferred: adding mid-setup hides the icon (see _ready); the guard above
	# also keeps two callers from queueing two owners.
	tree.root.add_child.call_deferred(owner)
	return owner
func _tray_visible(value:bool)->void:
	if supported and tray!=null:tray.visible=value
func _notification(what:int)->void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if supported and _close_armed:minimize()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_close_armed=false
func minimize()->void:
	minimized=true
	get_window().mode=Window.MODE_MINIMIZED
	_tray_visible(true)
	mode_changed.emit(true)
## Returns to the hub browser (leaving a running world) and raises the window.
func show_hub()->void:
	var scene:=get_tree().current_scene
	if scene!=null and scene.scene_file_path!=HUB_SCENE:
		get_tree().change_scene_to_file(HUB_SCENE)
	var window:=get_window()
	window.mode=Window.MODE_WINDOWED
	window.move_to_foreground()
	DisplayServer.window_move_to_foreground()
	minimized=false
	_tray_visible(true)
	mode_changed.emit(false)
func _menu_action(id:int)->void:
	match id:
		0:show_hub()
		1:quit_hub()
func quit_hub()->void:
	_tray_visible(false)
	get_tree().quit()
