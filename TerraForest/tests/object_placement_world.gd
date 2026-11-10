# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	run.call_deferred()
func run()->void:
	var slot:="recipe_generated_4644d8cfc8f97e43";var path:="user://worlds/"+slot+".trw"
	var checksum:=FileAccess.get_sha256(path)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray(["--world-slot="+slot,"--snapshot-readonly","--gameplay-construction","--temporary","--no-derived-cache"]),true)
	game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+120000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"existing world loads without writing its save")
	if failures:await finish();return
	game.set_process(false);game.set_physics_process(false);game.player.set_physics_process(false);game.player_view.entry.finish()
	game._clear_motion();game.fly=false;game.app_focused=true
	game.combat.action_input_owned=func()->bool:return true
	var placement:Node=game.object_placement;placement.action_input_owned=func()->bool:return true
	var base:Vector3=game.player.global_position+Vector3(0,8,0)
	var floor:=StaticBody3D.new();floor.collision_layer=1;game.add_child(floor);floor.global_position=base;floor.rotation.z=deg_to_rad(40)
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(8,.2,8);collider.shape=shape;collider.position.y=-.1;floor.add_child(collider)
	var surface:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=shape.size;surface.mesh=mesh;surface.position=collider.position;floor.add_child(surface)
	game.player.global_position=base+Vector3(0,0,2.5)
	game.camera.global_position=base+Vector3(.17,1.6,2.5);game.camera.look_at(base+Vector3(.17,0,.12))
	game.equipped_tool=222;game.tool_view.equip(222)
	await physics_frame;await physics_frame
	var grid:Dictionary=placement.target()
	check(grid.get("ok",false),"barrel uses whole-footprint support on a 40-degree shore fixture: "+str(grid.get("reason")))
	if failures:await finish();return
	check(is_equal_approx(grid.transform.origin.x,roundf(grid.transform.origin.x)) and is_equal_approx(grid.transform.origin.z,roundf(grid.transform.origin.z)),"grid mode aligns horizontal position to building cells")
	var obstruction:=StaticBody3D.new();obstruction.collision_layer=4;game.add_child(obstruction)
	obstruction.global_position=grid.bounds.position+Vector3(.1,.55,.1)
	var obstruction_collider:=CollisionShape3D.new();var obstruction_shape:=BoxShape3D.new();obstruction_shape.size=Vector3(.15,.6,.15);obstruction_collider.shape=obstruction_shape;obstruction.add_child(obstruction_collider)
	await physics_frame;await physics_frame
	check(not placement.target().get("ok",false),"fitted barrel still rejects another solid inside its volume")
	obstruction.free();await physics_frame;await physics_frame
	placement.free_placement=true
	var free_target:Dictionary=placement.target()
	check(free_target.get("ok",false) and not is_equal_approx(free_target.transform.origin.x,grid.transform.origin.x),"free placement retains the aimed sub-cell position")
	placement.free_placement=false;placement.refresh()
	check(placement.preview.visible and placement.preview.mesh.get_surface_count()==5 and placement.cells.multimesh.visible_instance_count>=2,"preview shows real barrel geometry and occupied building cells")
	await capture("barrel_grid")
	check(game.player_hud.inventory.grant(222,1,game.player_hud.inventory.snapshot().revision).ok,"carried barrel granted through shared inventory")
	var before:int=game.combat.barrels.get_ids().size()
	check(placement.place() and game.combat.barrels.get_ids().size()==before+1,"shore placement consumes one carried barrel and creates native model")
	check(not placement.place(),"overlapping or unpaid repeat placement is rejected")
	for item:int in placement.Catalog.ITEMS:
		check(placement.entries.has(item) and game.session_menu.dev_bag.catalog.has(item),"object is reachable from ordinary Dev Bag: "+placement.Catalog.ITEMS[item])
	game.equipped_tool=702;game.tool_view.equip(702);placement.free_placement=true
	game.camera.look_at(base+Vector3(-1.1,-.9,.12));placement.refresh()
	await capture("chair_free")
	check(FileAccess.get_sha256(path)==checksum,"player save is unchanged")
	await finish()
func capture(label:String)->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			for frame in 4:await process_frame
			await RenderingServer.frame_post_draw
			var path:=argument.trim_prefix("--capture-dir=").path_join(label+".png")
			check(root.get_texture().get_image().save_png(path)==OK,"rendered preview captured: "+label)
func finish()->void:
	if is_instance_valid(game):game.terrain.shutdown();game.free()
	await process_frame;await process_frame
	print("OBJECT_PLACEMENT_WORLD failures=",failures);quit(1 if failures else 0)
