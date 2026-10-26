# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var checks:=0
func verify(value:bool,label:String)->bool:checks+=1;return check(value,label)
func run()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	if not verify(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,60),"temporary native world ready"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.zombies.clear();game.zombies.population_enabled=false
	ProjectSettings.set_setting("terraforest/offscreen_session",false)
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var hud=game.player_hud;var inventory:RefCounted=hud.inventory
	var old:PackedByteArray=inventory.capture_storage_snapshot()
	verify(amount(6)==0,"existing starter inventory is not topped up with a torch")
	verify(inventory.grant_items(PackedInt64Array([102,1,204,2]),inventory.snapshot().revision).ok,"temporary fixture supplies crafting ingredients")
	var wood:=amount(102);var fibre:=amount(204);var recipe:=-1
	for index in hud.Crafting.RECIPES.size():
		if hud.Crafting.RECIPES[index].outputs==[6,1]:recipe=index
	verify(hud.Crafting.craft(inventory,recipe,1,inventory.snapshot().revision).ok and amount(6)==1 and amount(102)==wood-1 and amount(204)==fibre-2,"native crafting consumes one wood and two plant fibre for one torch")
	var crafted:PackedByteArray=inventory.capture_storage_snapshot()
	verify(inventory.restore_storage_snapshot(old) and amount(6)==0,"old inventory restores without torch grants")
	verify(inventory.restore_storage_snapshot(crafted) and amount(6)==1,"crafted torch survives inventory save/restore")
	hud.refresh();hud.equip_item(6)
	var view=game.tool_view.human
	verify(game.equipped_tool==6 and view.current==6 and view.torch_effects.burning and not game.structure_mode,"ordinary inventory selection holds and lights the torch")
	verify(not game.world_attack.attack() and game.tool_view.attack_profile().is_empty(),"torch cannot trigger a hidden combat or digging action")
	var point:Vector3=game.player.position+Vector3.UP*.3
	var dropped:Dictionary=game.pickups.drop_stack(inventory,hud.active_slot,inventory.snapshot().revision,point,1)
	verify(dropped.ok and amount(6)==0,"torch drops into the native collectible store")
	var saved_store:PackedByteArray=game.pickups.stores[6].capture_storage_snapshot()
	var saved_stack:PackedByteArray=game.pickups.stacks[6].capture_storage_snapshot()
	var without_torch:PackedByteArray=inventory.capture_storage_snapshot()
	verify(game.pickups.collect_near(point,inventory,func(_p):return true).ok and amount(6)==1,"torch recollects once")
	verify(inventory.restore_storage_snapshot(without_torch) and game.pickups.stores[6].restore_storage_snapshot(saved_store) and game.pickups.stacks[6].restore_storage_snapshot(saved_stack),"dropped ownership snapshot restores")
	verify(game.pickups.collect_near(point,inventory,func(_p):return true).ok and amount(6)==1 and not game.pickups.collect_near(point,inventory,func(_p):return true).ok,"restored torch recollects without duplication")
	hud.refresh();hud.equip_item(6)
	verify(preload("res://addons/player_runtime/item_icons.gd").texture(6)!=null and game.pickups.renderers.has(6),"inventory icon and batched drop model are registered")
	for frame in 20:view._process(1.0/60)
	if DisplayServer.get_name()!="headless":
		await process_frame;RenderingServer.force_draw(false);RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://reports/wooden_torch/world.png")
		# Lighting fixture affects this temporary session only, never world defaults.
		game.sun.light_energy=0;game.flashlight.visible=false
		for node in game.get_children():
			if node is WorldEnvironment:
				node.environment.background_mode=Environment.BG_COLOR;node.environment.background_color=Color("101923")
				node.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;node.environment.ambient_light_color=Color("8292a4")
				node.environment.ambient_light_energy=.08;node.environment.fog_enabled=false
		view.torch_effects.set_burning(false)
		var dark:=await light_picture("night_off")
		view.torch_effects.set_burning(true)
		var lit:=await light_picture("night_on")
		verify(lit>dark+.003,"held torch measurably illuminates real terrain in the dark fixture")
	hud.equip_item(1)
	verify(not view.torch_effects.burning and view.torch_effects.lamp.light_energy==0,"normal slot switch turns the torch off")
	await finish()
func light_picture(label:String)->float:
	for frame in 6:await process_frame
	RenderingServer.force_draw(false);RenderingServer.force_draw(false)
	var image:=root.get_texture().get_image();image.save_png("res://reports/wooden_torch/"+label+".png")
	var luminance:=0.0;var samples:=0
	# Foreground terrain only: exclude the hand, fire and UI.
	for y in range(int(image.get_height()*.56),int(image.get_height()*.79),8):
		for x in range(int(image.get_width()*.26),int(image.get_width()*.56),8):
			var pixel:=image.get_pixel(x,y);luminance+=(pixel.r+pixel.g+pixel.b)/3.0;samples+=1
	print("TORCH_LIGHT ",label," terrain_brightness=",luminance/samples)
	return luminance/samples
func finish()->void:
	game.shutdown_requested=true
	verify(await game.terrain.shutdown_after_edits(),"temporary world shuts down without saving user data")
	game.free();await process_frame;await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports/wooden_torch")
	FileAccess.open("res://reports/wooden_torch/world.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Temporary world; real inventory, crafting, equip, native pickup persistence, no user saves modified."},"  ")+"\n")
	print("WOODEN_TORCH_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
