extends SceneTree
var game:Node
var failures:=0
var checks:=0
var folder:="res://reports/developer_tools"
func check(condition:bool,message:String)->bool:
	checks+=1
	if not condition:failures+=1
	print("PASS " if condition else "FAIL ",message);return condition
func _initialize()->void:run.call_deferred()
func until(predicate:Callable,seconds:int)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func type_key(code:int,unicode_value:int)->void:
	for pressed:bool in [true,false]:
		var event:=InputEventKey.new();event.physical_keycode=code;event.keycode=code;event.unicode=unicode_value;event.pressed=pressed
		Input.parse_input_event(event);Input.flush_buffered_events()
func amount(inventory:RefCounted,item:int)->int:
	var total:=0
	for row:Dictionary in inventory.snapshot().slots:
		if row.item==item:total+=row.count
	return total
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.zombies.population_enabled=false;root.add_child(game)
	if not check(await until(func():return not game.loading_active and game.session_menu.ready_to_dock,60),"world and separated developer pages ready"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false
	var menu=game.session_menu;var bag=menu.dev_bag;var inventory:RefCounted=game.player_hud.inventory
	var original:PackedByteArray=inventory.capture_storage_snapshot()
	check(menu.navigation.keys()==["Session","Player","Graphics","Dev Bag","Dev Shapes","Dev Spawner","Developer","World"],"items, shapes, entities and serious diagnostics have separate navigation")
	check(menu.spawner.entries.keys()==["zombie","vehicle"] and bag.entries.has(501),"live vehicle spawn belongs in Dev Spawner while carried vehicle items stay in Dev Bag")
	menu.show_page("Dev Bag");bag.search.grab_focus()
	type_key(KEY_M,109);type_key(KEY_QUOTELEFT,96);await process_frame
	check(bag.search.text=="m`" and not game.world_map.opened and not menu.developer and menu.current_page=="Dev Bag","typing map and developer hotkeys stays inside search")
	bag.search.text="  TOPSOIL ";bag.filter_items()
	check(bag.entries[211].visible and not bag.entries[501].visible and not bag.empty.visible,"case-insensitive trimmed name search filters actual item tiles")
	bag.search.text="501";bag.filter_items();bag.category.select(1);bag.filter_items()
	check(bag.empty.visible,"category and text filters combine with a clear empty state")
	bag.category.select(0);bag.search.clear();bag.filter_items();await capture("dev_bag")
	var empty_state:Dictionary=inventory.snapshot()
	for row:Dictionary in empty_state.slots:row.item=0;row.count=0;row.wear=0;row.water_ml=0
	var all_granted:=true;var all_icons:=true
	for item:int in bag.catalog:
		inventory.restore(empty_state,inventory.snapshot().revision);bag.count.value=1;bag.entries[item].pressed.emit()
		all_granted=all_granted and amount(inventory,item)==1
		all_icons=all_icons and bag.entries[item].icon!=null
	check(bag.catalog.size()==game.player_hud.CATALOG.size()+game.player_hud.MATERIALS.size()+game.player_hud.RESOURCES.size() and all_granted,"every registered inventory item can be granted from the live catalog")
	check(all_icons,"all bag entries reuse baked item icons without live 3D rendering")
	inventory.restore(empty_state,inventory.snapshot().revision);bag.count.value=7;bag.entries[211].pressed.emit()
	check(amount(inventory,211)==7 and menu.opened and not menu.developer,"exact stack quantity is granted without closing the bag or changing gameplay mode")
	inventory.restore(empty_state,inventory.snapshot().revision);inventory.grant(1,32,inventory.snapshot().revision)
	var full:PackedByteArray=inventory.capture_storage_snapshot();var revision:int=inventory.snapshot().revision
	bag.entries[211].pressed.emit()
	check(inventory.capture_storage_snapshot()==full and inventory.snapshot().revision==revision and menu.message.text.contains("Nothing was added"),"full inventory rejection is atomic and explained")
	inventory.restore_storage_snapshot(original);game.player_hud.refresh()
	menu.show_page("Developer");await capture("developer")
	check(menu.mode_button.get_parent()==menu.pages.Developer and bag.search.is_visible_in_tree()==false,"Developer contains settings rather than item catalog")
	menu.show_page("Dev Spawner");menu.spawner.entries.zombie.pressed.emit()
	if not check(is_instance_valid(menu.spawner.last_spawn),"one click spawns an actual zombie on nearby supported ground: "+menu.message.text):await finish();return
	var zombie:CharacterBody3D=menu.spawner.last_spawn
	var identity:int=zombie.get_meta("world_zombie_id",0)
	var population=game.zombies.population
	check(identity==2501 and population.store.resident(identity).state==1 and not menu.developer,"explicit zombie uses persistent native identity without requiring editor mode")
	check(zombie.process_mode==Node.PROCESS_MODE_DISABLED and zombie.global_position.distance_to(game.player.global_position)>2.0,"spawn stays clear of the player and frozen while menu is open")
	await capture("dev_spawner")
	zombie.anatomy.hit("upper_arm_l",10.0,false,"melee")
	var vitals:PackedByteArray=zombie.anatomy.capture_vitals();var saved:PackedByteArray=population.capture()
	check(population.restore(saved),"actual world population component restores extended binary section")
	await process_frame
	game.zombies.population_enabled=true
	var restored:=await until(func():
		population.advance(game.player.global_position,true)
		return game.zombies.residents.any(func(resident):return resident.get_meta("world_zombie_id",0)==identity),30)
	game.zombies.population_enabled=false
	check(restored,"saved developer zombie reactivates as the same world resident")
	if restored:
		for resident in game.zombies.residents:
			if resident.get_meta("world_zombie_id",0)==identity:check(resident.anatomy.capture_vitals()==vitals,"reactivation preserves body and limb injuries")
	var stable:PackedByteArray=population.capture();var readiness:Callable=game.zombies.readiness;game.zombies.readiness=func(_bounds):return false
	menu.spawner.entries.zombie.pressed.emit()
	check(menu.spawner.last_spawn==null and population.capture()==stable,"unloaded spawn surface rejects without adding or replacing inhabitants")
	game.zombies.readiness=readiness
	type_key(KEY_ESCAPE,0)
	check(not menu.visible_ui() and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"Escape returns directly to play without an invisible UI blocker")
	for resident in game.zombies.residents:
		if resident.get_meta("world_zombie_id",0)==identity:game.camera.look_at(resident.global_position+Vector3.UP*1.2)
	game.set_physics_process(true)
	for frame in 5:await physics_frame
	await capture("spawned_zombie")
	await finish()
func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("DEVELOPER_TOOLS checks=",checks," failures=",failures);quit(1 if failures else 0)
