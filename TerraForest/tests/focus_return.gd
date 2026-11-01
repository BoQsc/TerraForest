# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func key(code:int,pressed:bool,alt:bool=false)->void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=pressed;event.alt_pressed=alt
	Input.parse_input_event(event);Input.flush_buffered_events()
func tap(code:int,alt:bool=false)->void:key(code,true,alt);key(code,false,alt)
func leave()->void:
	game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	game.session_menu.developer_hud._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game.session_menu._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
func resume(application_first:bool=true)->void:
	if application_first:game.session_menu.developer_hud._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	if not application_first:game.session_menu.developer_hud._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await process_frame;await process_frame
func _initialize()->void:run.call_deferred()
func run()->void:
	if "--desktop-focus-check" in OS.get_cmdline_user_args():
		# Establish the fixture before loading. The actual round trips never force
		# activation: only Windows Alt-Tab may return focus after the ready marker.
		root.grab_focus();await process_frame;await process_frame
		if not root.has_focus():
			check(false,"desktop fixture needs initial native window focus");quit(1);return
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+45000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"playable world ready")
	if game.loading_active:await finish();return
	await process_frame;await process_frame
	check(game.mouse_capture_requested and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"world readiness captures gameplay without a click")
	if "--desktop-focus-check" in OS.get_cmdline_user_args():
		await desktop_roundtrip(false)
		game.session_menu.set_open(true)
		await desktop_roundtrip(true)
		game.session_menu.set_open(false)
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false
	var menu=game.session_menu;var hud=game.player_hud;var tools=menu.developer_hud
	hud.equip_item(101);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	# Windows releases capture before delivering focus-out. Do not infer intent
	# from that already-visible mode, or require Alt to have reached the tool HUD.
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;leave();await resume()
	check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"focus return recaptures after OS release without an Alt event or click")
	for alt_flag:bool in [true,false]:
		key(KEY_ALT,true);tap(KEY_TAB,alt_flag)
		check(not hud.inventory_open and not hud.modal.visible,"Alt Tab cannot open inventory, modifier flag="+str(alt_flag))
		key(KEY_ALT,false)
		check(not tools.mouse_access and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"ordinary Alt release restores aiming")
	tap(KEY_TAB);tap(KEY_TAB,true)
	check(hud.inventory_open and hud.modal.visible and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Alt Tab also leaves an existing inventory open")
	tap(KEY_TAB)
	check(not hud.inventory_open and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"plain Tab still closes inventory")
	for application_first:bool in [true,false]:
		key(KEY_W,true);key(KEY_ALT,true)
		check(tools.mouse_access and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Alt grants temporary tool cursor access")
		leave()
		check(not game.app_focused and not tools.mouse_access and game.controls.direction()==Vector3.ZERO,"focus loss clears tool access and held movement")
		# No Alt key-up reaches the game before focus returns.
		await resume(application_first)
		check(game.app_focused and not tools.mouse_access and not hud.inventory_open and not menu.visible_ui() and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"focus return resumes aiming without Escape, application first="+str(application_first))
		key(KEY_W,false);key(KEY_W,true)
		check(game.controls.direction()!=Vector3.ZERO and game._movement_input_available(),"fresh movement input works immediately after focus return")
		var yaw:float=game.yaw;var motion:=InputEventMouseMotion.new();motion.relative=Vector2(12,0)
		Input.parse_input_event(motion);Input.flush_buffered_events()
		check(not is_equal_approx(game.yaw,yaw),"mouse look works immediately after focus return")
		key(KEY_W,false);key(KEY_ALT,false)
	# A tool dropdown may itself have keyboard focus when the application loses it.
	key(KEY_ALT,true)
	var popup:PopupMenu
	for control:Node in tools.content.get_children():
		if control is OptionButton:popup=control.get_popup();break
	if popup!=null:
		popup.popup();await process_frame
		check(popup.visible,"tool dropdown opens for focus-loss fixture")
		leave();await resume()
		check(not popup.visible and not tools.mouse_access and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"focus return dismisses stale tool popup without an invisible input blocker")
	else:check(false,"tool dropdown exists")
	key(KEY_ALT,false)
	# Real modal interfaces retain their cursor ownership across focus changes.
	for interface:String in ["inventory","session","tool settings","map"]:
		match interface:
			"inventory":tap(KEY_TAB)
			"session":menu.set_open(true)
			"tool settings":menu.open_current_tool()
			"map":menu.world_map.set_open(true)
		leave();await resume()
		await create_timer(0.65).timeout
		var opened:bool=hud.modal.visible if interface=="inventory" else (menu.world_map.opened if interface=="map" else menu.visible_ui())
		check(opened and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"focus return preserves open "+interface)
		match interface:
			"inventory":tap(KEY_TAB)
			"map":menu.world_map.set_open(false)
			_:menu.set_open(false)
		check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"closing "+interface+" returns to aiming")
	# Returning through a native child dialog can focus the root after app focus.
	key(KEY_ALT,true);leave();tools._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await process_frame
	check(tools.resume_mouse_after_focus,"capture waits while the main game window still lacks focus")
	game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN);root.focus_entered.emit()
	await process_frame;await process_frame
	check(not tools.resume_mouse_after_focus and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"root-window focus completes deferred capture after a dialog")
	key(KEY_ALT,false)
	# A queued focus callback must observe a menu opened before it executes.
	leave();game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN);menu.set_open(true)
	await process_frame;await process_frame
	check(menu.opened and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"menu opened during deferred focus return keeps its cursor")
	menu.set_open(false)
	check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"closing menu after deferred focus return resumes gameplay")
	# Reload/teleport uses the same ready transition, including loading offscreen.
	game._begin_loading("Focus regression loading transition")
	leave();await resume()
	check(game.loading_active and not game.mouse_capture_requested and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"focus return during loading does not capture")
	leave()
	deadline=Time.get_ticks_msec()+10000
	while game.loading_active and Time.get_ticks_msec()<deadline:
		game._update_loading();await process_frame
	check(not game.loading_active and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"loading completes while unfocused without capturing")
	await resume()
	check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"returning after background loading captures without a click")
	await finish()
func desktop_roundtrip(menu_open:bool)->void:
	print("DESKTOP_FOCUS_READY menu=",menu_open," pid=",OS.get_process_id())
	var deadline:=Time.get_ticks_msec()+15000
	while game.app_focused and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.app_focused,"real Alt-Tab leaves the game, menu="+str(menu_open))
	deadline=Time.get_ticks_msec()+15000
	while not game.app_focused and Time.get_ticks_msec()<deadline:await process_frame
	await process_frame;await process_frame
	check(game.app_focused and root.has_focus(),"real Alt-Tab returns native game focus, menu="+str(menu_open))
	await create_timer(0.65).timeout
	check(Input.mouse_mode==(Input.MOUSE_MODE_VISIBLE if menu_open else Input.MOUSE_MODE_CAPTURED),"real Alt-Tab restores correct cursor ownership without a click, menu="+str(menu_open))
func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("FOCUS_RETURN checks=",checks," failures=",failures);quit(1 if failures else 0)
