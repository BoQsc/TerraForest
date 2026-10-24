# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func screenshot(name:String)->void:
	game.structures.blocks.flush_bakes()
	game.set_process(false);game.shape_preview.hide();game.prefab_preview.hide();game.model_tool.preview.hide()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(name+".png"));game.set_process(true)
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--placement-evidence-dir="):evidence=argument.trim_prefix("--placement-evidence-dir=")
	if evidence.is_empty():evidence="res://reports/placement_targeting"
	DirAccess.make_dir_recursive_absolute(evidence)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"playable world ready"):await finish();return
	if not check(await wait_for(func():return not game.needs_floor_spawn,5),"player has settled onto the real forest floor"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false
	# Exercise the real streamed forest surface before the deterministic height fixtures.
	game.player_hud.equip_item(101)
	aim(game.player.position,game.player.position+Vector3(0,-.1,-2))
	var natural:Dictionary=game._structure_target(false)
	check(not natural.is_empty() and natural.get("placement_ok",false) and natural.has("support"),"streamed forest terrain supplies a supported placement target")
	if natural.get("placement_ok",false) and natural.has("support"):
		var start:int=amount(101)
		game._edit_structure(false)
		check(game.structures.blocks.get_cell(natural.target)==1 and amount(101)==start-1 and natural.support.maximum-natural.target.y<=.201,"real terrain placement limits burial and spends one brick")
		await screenshot("forest_ground_fit")
		var cell:Vector3i=natural.target
		game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,0]))
	var base:=Vector3i(game.player.position.floor())+Vector3i(0,10,0)
	game.structures.blocks.set_focus(Vector3(base))
	var floor:=StaticBody3D.new();floor.collision_layer=1;floor.collision_mask=0
	var box:=BoxShape3D.new();box.size=Vector3(10,.5,10)
	var collision:=CollisionShape3D.new();collision.shape=box;floor.add_child(collision)
	var visual:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=box.size;visual.mesh=mesh
	var material:=StandardMaterial3D.new();material.albedo_color=Color("6b7959");visual.material_override=material;floor.add_child(visual)
	game.terrain.add_child(floor);floor.global_position=Vector3(base)+Vector3(.5,.57,.5)
	aim(Vector3(base)+Vector3(0,1,3),Vector3(base)+Vector3(.5,.82,.5))
	game.camera.global_position=Vector3(base)+Vector3(.5,2.4,2.8);game.camera.look_at(Vector3(base)+Vector3(.5,.82,.5))
	for i in 4:await physics_frame
	game.player_hud.equip_item(101)
	var hit:Dictionary=game._structure_target(false)
	check(not hit.is_empty() and hit.get("placement_ok",false) and hit.target.y==base.y+1,"aimed brick target lifts out of deeply intersecting terrain")
	game._prefab_preview_timer=0;game._update_prefab_preview(.2)
	check(game.shape_preview.visible and game.shape_preview.position==Vector3(hit.target),"block preview uses the same corrected grid cell")
	var before:int=amount(101)
	game._edit_structure(false)
	check(game.structures.blocks.get_cell(hit.target)==1 and amount(101)==before-1,"click publishes exactly the previewed paid block")
	await screenshot("block_ground_fit")
	var placed:Vector3i=hit.target
	game.camera.look_at(Vector3(placed)+Vector3(.5,1,.5))
	var stack:Dictionary=game._structure_target(false)
	check(stack.get("placement_ok",false) and stack.target==placed+Vector3i.UP,"authored top face preserves exact grid stacking")
	game.camera.global_position=Vector3(base)+Vector3(.5,1.5,2.8)
	game.camera.look_at(Vector3(placed)+Vector3(.5,.5,1))
	var side:Dictionary=game._structure_target(false)
	check(side.get("placement_ok",false) and side.target==placed+Vector3i(0,0,1),"authored side face preserves exact grid adjacency")
	# Terrain occupying an adjacent cell must not silently move that wall up a cell.
	var covered:=StaticBody3D.new();covered.collision_layer=1;covered.collision_mask=0
	var cover_shape:=CollisionShape3D.new();var cover_box:=BoxShape3D.new();cover_box.size=Vector3(1,.5,.8);cover_shape.shape=cover_box;covered.add_child(cover_shape)
	game.terrain.add_child(covered);covered.global_position=Vector3(placed)+Vector3(.5,.1,1.6)
	for i in 3:await physics_frame
	var rejected:Dictionary=game._structure_target(false)
	before=amount(101);game._edit_structure(false)
	check(not rejected.get("placement_ok",true) and rejected.target==side.target and amount(101)==before and game.structures.blocks.get_cell(side.target)==0,"covered adjacent cell is rejected without moving the wall or taking materials")
	covered.free()
	game.structures.blocks.set_cells(PackedInt32Array([placed.x,placed.y,placed.z,0]))
	# A shallow overlap should remain easy to place without a needless grid jump.
	floor.position.y=base.y-.13
	for i in 3:await physics_frame
	game.camera.global_position=Vector3(base)+Vector3(.5,2.4,2.8)
	game.camera.look_at(Vector3(base)+Vector3(.5,.12,.5))
	hit=game._structure_target(false)
	check(hit.get("placement_ok",false) and hit.target.y==base.y,"small ground overlap remains accepted in the lower cell")
	# Use the real assembly catalog and native paid insertion on a gentle slope.
	floor.position.y=base.y+.57;floor.rotation.z=deg_to_rad(10)
	for i in 3:await physics_frame
	game.camera.look_at(Vector3(base)+Vector3(.5,.82,.5));game.player_hud.equip_item(4)
	var tool=game.model_tool;var index:=-1
	for i:int in tool.catalog.size():
		if tool.catalog[i].title=="Wooden table":index=i;break
	if not check(index>=0,"ordinary furniture catalog is available"):await finish();return
	tool.select(index);tool.edit_available=true
	var object_hit:Dictionary=tool.target()
	check(not object_hit.is_empty() and object_hit.get("placement_ok",false) and object_hit.support.maximum-object_hit.support.bottom<=.031,"object target samples its footprint instead of using one clicked height")
	tool.refresh()
	check(tool.preview_valid and tool.preview.global_transform.is_equal_approx(object_hit.transform),"object preview matches the accepted support fit")
	before=amount(102)
	var id:int=tool.edit(false)
	check(id>0 and amount(102)<before,"supported furniture places through its normal paid transaction")
	await screenshot("object_ground_fit")
	if id>0:tool.history.erase(tool.catalog[index].collection,id)
	floor.rotation.z=deg_to_rad(35)
	for i in 3:await physics_frame
	object_hit=tool.target();tool.refresh()
	var steep_inventory:PackedByteArray=game.player_hud.capture_snapshot()
	check(not object_hit.is_empty() and not object_hit.get("placement_ok",true) and not tool.preview_valid and tool.edit(false)==0 and steep_inventory==game.player_hud.capture_snapshot(),"excessively uneven furniture placement turns red and rejects without payment")
	# Unknown collision must reject before taking any materials.
	var inventory:PackedByteArray=game.player_hud.capture_snapshot()
	tool.support_ready=func(_bounds:AABB)->bool:return false
	check(tool.edit(false)==0 and inventory==game.player_hud.capture_snapshot(),"unavailable support rejects placement without charging materials")
	tool.support_ready=game._placement_collision_ready
	floor.free()
	await finish()
func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
	print("PLACEMENT_TARGETING_WORLD failures=",failures);quit(1 if failures else 0)
