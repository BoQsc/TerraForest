# SPDX-License-Identifier: 0BSD
extends SceneTree
const DIR="res://reports/furnished_world/"
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func state(game: Node) -> Dictionary:
	var result:={"blocks":game.structures.blocks.capture_snapshot(),"roads":game.road_palette.capture_anchors(),"water":game.lakes.capture_snapshot(),"inventory":game.player_hud.capture_snapshot(),"beam":game.structures.model("architecture/metal_beam/v1").capture_snapshot()}
	for name in ["table","chair","shelf"]: result[name]=game.structures.model("furniture/"+name+"/v1").capture_snapshot()
	return result
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DIR+"manifest.json"))
	var reopen: bool="--reopen-furnished" in OS.get_cmdline_user_args()
	var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active and game.terrain.save_slot==manifest.slot,"separate furnished save opens")
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.fly=true;game.needs_floor_spawn=false
	check(game.structures.blocks.stats().cells==1872 and game.road_palette.prepared_streets.size()==4,"all cottages and connected streets retained")
	var origin:=Vector3(manifest.target[0],manifest.target[1],manifest.target[2])
	var rooms: Array[Transform3D]=[]
	for street in range(2):
		var road: Dictionary=game.road_palette.prepared_streets[street]
		var z: float=road.ends[0].z
		for side in range(2):
			rooms.append(Transform3D(Basis(Vector3.UP,side*PI),Vector3(origin.x+4.5,origin.y+2,z+(-13.5 if side==0 else 13.5))))
	if reopen:
		var expected: Dictionary=FileAccess.open(DIR+"expected.bin",FileAccess.READ).get_var()
		for name: String in expected: check(state(game)[name]==expected[name],"exact saved "+name+" state restored")
	else:
		check(game.structures.model("architecture/metal_beam/v1").remove_instances(PackedInt64Array([9001])),"remove legacy floating checkpoint test prop")
		for name in ["table","chair","shelf"]:
			if not game.structures.model("furniture/"+name+"/v1").get_ids().is_empty(): check(false,"creation refuses populated furniture collections");game.terrain.shutdown();quit(1);return
		for room in rooms:
			for i in range(3):
				var entry: Dictionary=game.model_tool.catalog[3+i]
				var local:=Vector3(-1.8,0,-0.5) if i==0 else (Vector3(-1.8,0,1.0) if i==1 else Vector3(2.0,0,-2.8))
				var pose: Transform3D=room*Transform3D(Basis(Vector3.UP,PI if i==2 else 0.0),local)
				var id: int=game.model_tool.history.insert(entry.collection,game.model_tool.records(pose,entry.collection),AABB(Vector3(-999,-999,-999),Vector3.ONE))
				check(id>0,"furnishing admitted: "+entry.title)
	for room in rooms:
		game.player.position=room.origin+Vector3(0,0.1,0);game.structures.set_model_focus(game.player.position)
		for frame in range(30): await physics_frame
		var floor_hit: Dictionary=game.structures.blocks.raycast_scene(room.origin+Vector3.UP,room.origin-Vector3.UP,3,[])
		check(not floor_hit.is_empty() and absf(floor_hit.position.y-room.origin.y)<0.1,"interior floor supports the authored layout")
		var a: Vector3=room*Vector3(0,1,4.5);var b: Vector3=room*Vector3(0,1,-3)
		check(game.structures.blocks.raycast_scene(a,b,3,[game.player.get_rid()]).is_empty(),"central interior sightline stays clear")
		var start:=Transform3D(Basis.IDENTITY,room*Vector3(0,0.05,4.5))
		check(not game.player.test_move(start,room.basis*Vector3(0,0,-7.5)),"player capsule can cross the furnished central aisle")
	for name in ["table","chair","shelf"]:check(game.structures.model("furniture/"+name+"/v1").get_ids().size()==4,"four persistent "+name+" objects")
	game.player.position=rooms[0]*Vector3(0,0.1,3.5)
	game.fly=false;game.yaw=0.0;game.pitch=-0.15
	game.player.rotation.y=game.yaw
	game.camera.global_position=rooms[0]*Vector3(0,1.7,3.5);game.camera.look_at(rooms[0]*Vector3(0,0.8,-1))
	for frame in range(30): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR+("reopened.png" if reopen else "furnished.png"))
	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample and Engine.max_fps==60,"fullscreen1080p cap60")
	if not reopen and failures==0:
		var expected:=FileAccess.open(DIR+"expected.bin",FileAccess.WRITE);expected.store_var(state(game));expected.close()
	var saved: Array=[];game.terrain.save_completed.connect(func(ok: bool):saved.append(ok))
	if failures==0:
		game.terrain.changed_since_save=true;game.terrain.save_world();deadline=Time.get_ticks_msec()+15000
		while saved.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check(not saved.is_empty() and saved[0],"normal world save commits furnished content")
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"normal world shutdown")
	game.free();await process_frame;await process_frame
	print("FURNISHED_WORLD failures=",failures);quit(1 if failures else 0)
