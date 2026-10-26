extends "res://tests/container_e_toggle.gd"

func escape_once()->void:
	await press(KEY_ESCAPE);await release(KEY_ESCAPE)

func pause_cycle()->void:
	await escape_once()
	check(game.session_menu.opened,"fresh Escape with no active UI opens the pause menu")
	await escape_once()
	check(not game.session_menu.opened and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"Escape closes pause menu and returns control")

func dismiss(label:String,closed:Callable)->void:
	await press(KEY_ESCAPE)
	check(closed.call(),"Escape closes "+label)
	check(not game.session_menu.opened,"closing "+label+" does not also open pause menu")
	await press(KEY_ESCAPE,true)
	check(not game.session_menu.opened,"Escape repeat does not open pause after "+label)
	await release(KEY_ESCAPE)
	check(not game.player_hud.inventory_open and game.player_hud.enabled,"closing "+label+" restores HUD input")
	check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"closing "+label+" restores camera capture")

func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://reports/escape_ui_priority")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"escape evidence saved: "+label)

func run()->void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"temporary world ready"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var menu=game.session_menu
	var origin:Vector3=game.player.position+Vector3(0,8,-3)
	var corpse:int=game.corpse_loot.store.create_corpse(origin,0,1703)
	if not check(corpse>0,"native corpse contents fixture created"):await finish();return
	var original_picker:Callable=game.corpse_loot.ui.external_picker
	game.corpse_loot.ui.external_picker=func(_hit:Variant=null)->int:return corpse
	if not check(game.corpse_loot.ui.try_open(),"corpse storage opens"):await finish();return
	game.corpse_loot.ui.quantity.get_line_edit().grab_focus()
	if "--escape-corpse-only" not in OS.get_cmdline_user_args():await capture("corpse-before-escape")
	await dismiss("corpse storage",func()->bool:return not game.corpse_loot.ui.opened)
	if "--escape-corpse-only" in OS.get_cmdline_user_args():
		game.corpse_loot.ui.close();await finish();return
	await capture("corpse-closed")
	game.corpse_loot.ui.external_picker=original_picker
	await pause_cycle()
	game.player_hud.set_open(true)
	await dismiss("inventory",func()->bool:return not game.player_hud.modal.visible)
	await pause_cycle()
	var chest:Node3D=game.storage.collection
	var identity:int=chest.insert_instance(game.model_tool.records(Transform3D(Basis.IDENTITY,origin),chest),AABB())
	if not check(identity>0,"actual chest inserted"):await finish();return
	chest.set_collision_focus(origin)
	aim(origin+Vector3(0,0.05,2),origin+Vector3(0,0.4,0))
	for frame in 12:await physics_frame;await process_frame
	if not check(game.storage.try_open(),"chest storage opens"):await finish();return
	await dismiss("chest storage",func()->bool:return not game.storage.opened)
	await pause_cycle()
	chest.remove_instances(PackedInt64Array([identity]))
	game.world_map.set_open(true)
	if check(game.world_map.opened,"map opens"):
		await dismiss("world map",func()->bool:return not game.world_map.opened)
		await pause_cycle()
	menu.toggle_developer();menu.open_tool_page("Terrain")
	if check(menu.workspace,"tool workspace opens"):
		await dismiss("tool workspace",func()->bool:return not menu.workspace)
		await pause_cycle()
	menu.open_tool_page("Terrain")
	var popup:PopupMenu=menu.tool_workspace.box_mode.get_popup()
	popup.popup(Rect2i(700,300,260,160));await process_frame
	await escape_once()
	check(not popup.visible and menu.workspace and not menu.opened,"Escape closes a dropdown before its tool workspace")
	await dismiss("workspace after dropdown",func()->bool:return not menu.workspace)
	await pause_cycle()
	menu.show_page("Dev Bag");menu.dev_bag.search.grab_focus()
	await escape_once()
	check(not menu.opened and not game.player_hud.inventory_open,"Escape closes Dev Bag even when search owns focus")
	await pause_cycle()
	await press(KEY_ALT)
	if check(menu.developer_hud.mouse_access,"Alt tool controls receive cursor access"):
		await dismiss("Alt tool controls",func()->bool:return not menu.developer_hud.mouse_access)
	await release(KEY_ALT)
	await pause_cycle()
	var developer_before:bool=menu.developer
	await press(KEY_QUOTELEFT)
	check(menu.tilde_down>=0 and not menu.player_actions.opened,"player action hold starts before wheel opens")
	await dismiss("pending player action wheel",func()->bool:return menu.tilde_down<0 and not menu.player_actions.opened)
	await release(KEY_QUOTELEFT)
	check(menu.developer==developer_before,"cancelled hold release cannot toggle developer mode")
	await pause_cycle()
	await press(KEY_QUOTELEFT)
	if check(await wait_for(func():return menu.player_actions.opened,3),"player action wheel opens"):
		await dismiss("player action wheel",func()->bool:return not menu.player_actions.opened)
	await release(KEY_QUOTELEFT)
	await pause_cycle()
	for opened in [false,true]:
		game.vehicle_radial.held_since=Time.get_ticks_msec();game.vehicle_radial.opened=opened;game.vehicle_radial.view.show()
		if opened:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		await dismiss("vehicle action wheel" if opened else "pending vehicle action wheel",func()->bool:return not game.vehicle_radial.opened and game.vehicle_radial.held_since<0)
		await release(KEY_E)
		await pause_cycle()
	menu.set_open(true)
	var actions:Array=[]
	menu.confirm("Escape priority test",func():actions.append(true))
	await process_frame
	await escape_once()
	check(not menu.confirmation.visible and menu.opened and actions.is_empty(),"Escape cancels confirmation without closing its parent menu or executing action")
	await escape_once()
	check(not menu.opened,"next Escape closes the parent menu")
	await pause_cycle()
	await escape_once();await capture("pause-menu")
	await escape_once()
	await finish()
