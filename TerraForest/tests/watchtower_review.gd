# SPDX-License-Identifier: 0BSD
extends SceneTree
const Recipe=preload("res://addons/exploration/watchtower.gd")
const Contact=preload("res://addons/structures/terrain_contact.gd")
const Turns=preload("res://addons/exploration/cave_layouts.gd")
var checks:=0
var failures:=0
var folder:=""
var resource_path:="res://addons/exploration/watchtower_w1.tres"
var stage:Node3D
var player:CharacterBody3D
var motor:RefCounted
var camera:Camera3D
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):folder=argument.trim_prefix("--review-output=")
		if argument.begins_with("--watchtower-resource="):resource_path=argument.trim_prefix("--watchtower-resource=")
	run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func walk(target:Vector3)->bool:
	for frame in 240:
		await physics_frame
		var offset:=target-player.position;offset.y=0
		if offset.length()<.18 and absf(player.position.y-target.y)<.15:return true
		player.velocity=motor.walking_velocity(offset.normalized(),player.velocity,1./60.,false,player.is_on_floor(),false)
		motor.move_grounded(player,1./60.)
	print("WATCHTOWER_BLOCKED target=",target," actual=",player.position)
	return false
func capture(label:String,position:Vector3,target:Vector3)->void:
	if folder.is_empty():return
	camera.position=position;camera.look_at(target)
	for frame in 8:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func run()->void:
	if not folder.is_empty():DirAccess.make_dir_recursive_absolute(folder)
	motor=ClassDB.instantiate("NativePlayerMovement")
	for rotation in 4:
		stage=Node3D.new();root.add_child(stage)
		var structures:=preload("res://addons/structures/structures_world.gd").new();stage.add_child(structures)
		preload("res://addons/structures/storage_catalog.gd").register(structures)
		var asset:=Recipe.build(structures.blocks)
		check(asset!=null and Contact.describe(asset).ok,"watchtower has valid grid and shared terrain-contact metadata")
		if asset==null:quit(1);return
		if rotation==0:
			check(asset.get_cell_count()<600,"one bounded recipe with fewer than 600 independent cells")
			if "--bake-watchtower" in OS.get_cmdline_user_args():check(ResourceSaver.save(asset,"res://addons/exploration/watchtower_w1.tres")==OK,"original watchtower resource baked")
			var baked:Resource=load(resource_path)
			check(baked!=null and baked.get_records()==asset.get_records() and baked.get_model_attachments()==asset.get_model_attachments() and baked.get_meta("walk_route")==asset.get_meta("walk_route"),"baked resource matches exact authoring cells, attachments and circulation")
			print("WATCHTOWER_CELLS ",asset.get_cell_count())
		var placement=ClassDB.instantiate("NativePrefabPlacement")
		var placed:Dictionary=placement.place(structures.blocks,asset,Vector3i.ZERO,rotation,structures.model_collections(),[])
		check(placed.get("ok",false),"grid structure and supply chest place atomically at rotation "+str(rotation))
		check(preload("res://addons/structures/foundation_check.gd").block_model_support(structures.blocks,asset,Vector3i.ZERO,rotation,structures.model_collections()).get("ok",false),"actual upper-floor chest bounds have continuous block support and clearance")
		structures.blocks.set_focus(Vector3(0,4,0));structures.blocks.set_collision_radius(48);structures.blocks.flush_bakes();structures.set_model_focus(Vector3(0,4,0))
		var saved:PackedByteArray=structures.blocks.capture_snapshot()
		check(structures.blocks.restore_snapshot(saved) and structures.blocks.capture_snapshot()==saved,"independent blocks restore exact binary state")
		var footing:=Vector3i(Turns.turn(Vector3(2.5,6.5,6.5),rotation).floor())
		check(structures.blocks.set_cells(PackedInt32Array([footing.x,footing.y,footing.z,0])) and not preload("res://addons/structures/foundation_check.gd").block_model_support(structures.blocks,asset,Vector3i.ZERO,rotation,structures.model_collections()).get("ok",false),"missing upper-deck floor rejects supply publication")
		check(structures.blocks.restore_snapshot(saved),"restore upper-deck support after rejection")
		var obstruction:=Vector3i(Turns.turn(Vector3(1.5,7.5,6.5),rotation).floor())
		check(structures.blocks.set_cells(PackedInt32Array([obstruction.x,obstruction.y,obstruction.z,1])) and not preload("res://addons/structures/foundation_check.gd").block_model_support(structures.blocks,asset,Vector3i.ZERO,rotation,structures.model_collections()).get("ok",false),"intersecting upper-deck solid rejects supply publication")
		check(structures.blocks.restore_snapshot(saved),"restore clear supply bounds after rejection")
		var probes:=PackedVector3Array()
		for column in [0,6]:
			for row in [0,4,8]:
				for sample_index in 84:probes.append(Turns.turn(Vector3(column+.5,sample_index*.125+.0625,row+.5),rotation))
		var solid:PackedByteArray=structures.blocks.sample_solid(probes)
		check(solid.size()==probes.size() and solid.count(1)==solid.size(),"every support column remains continuous from footing through roof joint")
		var removed:=Vector3i(Turns.turn(Vector3(3.5,12.5,5.5),rotation).floor())
		var neighbor:=Vector3i(Turns.turn(Vector3(3.5,12.5,6.5),rotation).floor())
		var neighbor_word:int=structures.blocks.get_cell(neighbor)
		check(structures.blocks.get_cell(removed)>0 and neighbor_word>0 and structures.blocks.set_cells(PackedInt32Array([removed.x,removed.y,removed.z,0])) and structures.blocks.get_cell(removed)==0 and structures.blocks.get_cell(neighbor)==neighbor_word,"one roof piece removes without removing the adjacent piece")
		check(structures.blocks.restore_snapshot(saved),"restore local removal before physical route checks")
		structures.blocks.flush_bakes()
		player=CharacterBody3D.new();player.collision_mask=7;player.collision_layer=8;player.floor_snap_length=.35;player.floor_max_angle=deg_to_rad(48.);player.floor_constant_speed=true;player.safe_margin=.004;player.max_slides=8;player.wall_min_slide_angle=0
		var shape:=CapsuleShape3D.new();shape.radius=.34;shape.height=1.8
		var collider:=CollisionShape3D.new();collider.shape=shape;collider.position.y=.9;player.add_child(collider);stage.add_child(player)
		var route:PackedVector3Array=asset.get_meta("walk_route").duplicate()
		player.position=Turns.turn(route[0],rotation)
		for frame in 8:await physics_frame
		var reached:=true
		for point:Vector3 in route.slice(1):
			if not await walk(Turns.turn(point,rotation)):reached=false;break
		check(reached,"native player climbs both flights and reaches lookout supplies, rotation "+str(rotation))
		if reached:
			route.reverse()
			for point:Vector3 in route.slice(1):
				if not await walk(Turns.turn(point,rotation)):reached=false;break
			check(reached,"native player returns down both flights, rotation "+str(rotation))
		if rotation==0 and not folder.is_empty():
			var floor_body:=StaticBody3D.new();floor_body.position=Vector3(0,.875,0);stage.add_child(floor_body)
			var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(70,70);ground.mesh=plane
			var material:=StandardMaterial3D.new();material.albedo_color=Color(.26,.32,.23);material.roughness=1;ground.material_override=material;floor_body.add_child(ground)
			var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.shadow_enabled=true;stage.add_child(sun)
			var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.52,.65,.73);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color(.7,.76,.8);environment.environment.ambient_light_energy=.65;stage.add_child(environment)
			camera=Camera3D.new();camera.current=true;camera.far=150;stage.add_child(camera)
			await capture("watchtower_front",Vector3(-9,8,-10),Vector3(3.5,6,4))
			await capture("watchtower_back",Vector3(18,11,22),Vector3(3.5,6,4))
			await capture("watchtower_stairs",Vector3(3.3,2.7,-3),Vector3(3.2,3.5,4.8))
			await capture("watchtower_deck",Vector3(4.7,8.6,.8),Vector3(3,7.8,6.8))
		stage.queue_free();await process_frame;await physics_frame
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED,"review never captures desktop pointer")
	print("WATCHTOWER_REVIEW checks=",checks," failures=",failures)
	quit(1 if failures else 0)
