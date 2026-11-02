# SPDX-License-Identifier: 0BSD
extends SceneTree
const City=preload("res://addons/structures/city_catalog.gd")
const Expansion=preload("res://addons/structures/expansion_catalog.gd")
var checks:=0
var failures:=0
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var output:="res://reports/door_dimensions"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--door-output="):output=arg.trim_prefix("--door-output=")
	var structures:=preload("res://addons/structures/structures_world.gd").new();root.add_child(structures)
	check(structures.prepare(),"native structures ready")
	preload("res://addons/structures/furniture_catalog.gd").register(structures)
	preload("res://addons/structures/storage_catalog.gd").register(structures)
	preload("res://addons/structures/window_catalog.gd").register(structures)
	var door:Dictionary=preload("res://addons/structures/door_catalog.gd").register(structures)
	check(is_equal_approx(door.scale.y*2.2,2.0),"new player-placed wooden doors default to two blocks")
	var assets:Array=Expansion.assets()
	for index in City.IDS.size():assets.append(City.asset(index))
	var empty:PackedByteArray=structures.capture_storage_snapshot()
	var transaction:RefCounted=ClassDB.instantiate("NativePrefabPlacement")
	for asset:Resource in assets:
		structures.restore_storage_snapshot(empty)
		var result:Dictionary=transaction.place(structures.blocks,asset,Vector3i.ZERO,0,structures.model_collections(),[])
		check(result.get("ok",false),"full prefab publishes: "+asset.resource_name)
		var dimensions_ok:=true;var clearance_ok:=true;var lintels_ok:=true;var count:=0
		for row:Dictionary in asset.get_model_attachments():
			if row.model!="architecture/wooden_door/v1":continue
			count+=1
			var pose:Transform3D=row.transform
			dimensions_ok=dimensions_ok and absf(pose.basis.y.length()*2.2-2.0)<.0001
			var visual:AABB=pose*door.mesh.get_aabb()
			dimensions_ok=dimensions_ok and visual.size.y<=2.001
			var center:=pose*Vector3(.5,0,0)
			var samples:=PackedVector3Array([center+Vector3.UP*.1,center+Vector3.UP*1.79,center+Vector3.UP*1.99])
			clearance_ok=clearance_ok and not structures.blocks.sample_solid(samples).has(1)
			lintels_ok=lintels_ok and structures.blocks.sample_solid(PackedVector3Array([center+Vector3.UP*2.05]))[0]==1
		check(count>0 and dimensions_ok,"all door collision/visual transforms are two blocks: "+asset.resource_name)
		check(clearance_ok and lintels_ok,"two clear rows and solid lintel: "+asset.resource_name)
	if "--door-photo" in OS.get_cmdline_user_args():
		# Actual production church, cropped to the personnel door and cell courses.
		structures.restore_storage_snapshot(empty)
		var asset:Resource=Expansion.asset("church_c1")
		if "--door-baseline" in OS.get_cmdline_user_args():asset=load("res://reports/door_dimensions/original_church.tres")
		check(transaction.place(structures.blocks,asset,Vector3i.ZERO,0,structures.model_collections(),[]).get("ok",false),"photo building publishes")
		var pose:Transform3D=asset.get_model_attachments().filter(func(row):return row.model=="architecture/wooden_door/v1")[-1].transform
		var center:=pose*Vector3(.5,0,0)+Vector3.UP*1.1
		structures.blocks.set_focus(center);structures.blocks.set_collision_radius(64);structures.blocks.flush_bakes();structures.set_model_focus(center)
		var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.5,.6,.7);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.8;root.add_child(environment)
		var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);root.add_child(sun)
		var camera:=Camera3D.new();root.add_child(camera);camera.current=true;camera.global_position=center+pose.basis.z*6+Vector3(1,1,0);camera.look_at(center)
		var fill:=OmniLight3D.new();fill.omni_range=14;fill.light_energy=3;root.add_child(fill);fill.global_position=camera.global_position
		for frame in 12:await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(output)
		root.get_texture().get_image().save_png(output.path_join("church_baseline.png" if "--door-baseline" in OS.get_cmdline_user_args() else "church_two_blocks.png"))
	structures.free();print("DOOR_DIMENSIONS checks=",checks," failures=",failures);quit(1 if failures else 0)
