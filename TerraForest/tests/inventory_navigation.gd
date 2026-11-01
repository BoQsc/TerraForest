# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var folder:="res://reports/inventory_navigation"
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)
func photograph(label:String)->void:
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):folder=argument.trim_prefix("--evidence=")
	run.call_deferred()
func run()->void:
	var hud=preload("res://addons/player_runtime/player_hud.gd").new();root.add_child(hud)
	var portrait:Control=hud.character_panel.portrait
	check(portrait.viewport==null,"backpack startup does not create another 3D scene")
	hud.set_open(true)
	var labels:Array=[]
	for button in hud.side_tabs.get_children():
		if button is Button and button.name!="InventoryClose":labels.append(button.text)
	check(labels==["Backpack","Character","Skills","Journal","Map","Quests"],"one top navigation exposes the requested destinations")
	check(hud.active_tab=="Backpack" and hud.crafting_content.visible and hud.slots.size()==22 and hud.belt.size()==10,"backpack retains crafting and never duplicates belt storage")
	var before:=Time.get_ticks_usec();hud.show_side("Character")
	print("PORTRAIT_BUILD_US ",Time.get_ticks_usec()-before)
	for frame in 4:await process_frame
	check(portrait.viewport!=null and portrait.model_resource!=null and hud.character_panel.visible and hud.backpack_panel.visible,"Character shows current body and equipment beside the backpack")
	check(portrait.viewport.size==Vector2i(384,448) and portrait.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"small portrait renders once instead of every frame")
	check(portrait.actor.process_mode==Node.PROCESS_MODE_DISABLED and not portrait.animation_player.is_playing(),"portrait uses a sampled authored idle pose without runtime animation work")
	var count:int=portrait.renders;var angle:float=portrait.actor.rotation.y
	await photograph("character-front")
	portrait.rotate_view(1)
	for frame in 3:await process_frame
	check(portrait.renders==count+1 and portrait.actor.rotation.y!=angle and portrait.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"rotation requests exactly one additional rendered view")
	await photograph("character-side")
	hud.inventory.grant_items(PackedInt64Array([301,1,302,1,303,1]),hud.inventory.snapshot().revision);hud.refresh()
	for identity in [301,302,303]:
		var slot:=-1
		for index in 32:
			if hud.inventory.snapshot().slots[index].item==identity:slot=index;break
		var data:Dictionary=hud.drag_data("player",slot);var destination:int=identity-301
		check(hud.character_panel.accepts_drag("equipment",destination,data),"matching equipment slot accepts carried item %d"%identity)
		hud.character_panel.drop_stack("equipment",destination,data)
		check(hud.equipment.snapshot(1).slots[destination].item==identity,"equipment transaction installs item %d"%identity)
		check(not hud.character_panel.accepts_drag("equipment",destination,data),"stale equipment drag is rejected")
	await photograph("character-equipped")
	var worn:Dictionary=hud.character_panel.drag_data("equipment",0);hud.drop_stack("player",31,worn)
	check(hud.equipment.snapshot(1).slots[0].item==0 and hud.inventory.snapshot().slots[31].item==301,"equipment can return to the actual backpack")
	hud.show_side("Skills");count=portrait.renders
	for frame in 12:await process_frame
	check(not portrait.active and portrait.renders==count and portrait.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"hidden character neither rerenders nor discards its cached view")
	hud.show_side("Journal");check(hud.journal_panel.visible and not hud.character_panel.visible,"Journal uses the same navigation shell")
	hud.show_side("Quests");check(hud.quests_panel.visible,"unfinished quest integration is explicit rather than a fabricated mission")
	hud.show_side("Map");check(not hud.backpack_panel.visible and not hud.crafting_panel.visible and hud.side_tabs.visible,"map destination reserves the shared content area without duplicate panels")
	hud.show_side("Character");check(portrait.renders==count+1,"reopening the portrait reuses its existing bounded viewport")
	var escape:=InputEventKey.new();escape.physical_keycode=KEY_ESCAPE;escape.pressed=true;hud._input(escape)
	check(not hud.inventory_open and not portrait.active and not hud.modal.visible,"Escape closes the active inventory destination")
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"UI checks never capture or reposition the pointer")
	hud.free();print("INVENTORY_NAVIGATION checks=",checks," failures=",failures);quit(1 if failures else 0)
