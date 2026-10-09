# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
const DIR := "res://reports/settlement_walk/"
var game: Node
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DIR+"source.json"))
	game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"saved settlement ready")
	if game.terrain.save_slot != source.slot:
		check(false,"refuse to edit a slot other than the disposable source manifest")
		game.terrain.shutdown();quit(1);return
	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample and Engine.max_fps==60,"fullscreen1080p cap60")
	var expected_path: String=DIR+"blocks.bin"
	if "--repair-entrances" not in OS.get_cmdline_user_args() and FileAccess.file_exists(expected_path):
		check(game.structures.blocks.capture_snapshot()==FileAccess.get_file_as_bytes(expected_path),"exact repaired blocks restored in fresh process")
	game.set_physics_process(false);game._clear_motion();game.fly=false;game.needs_floor_spawn=false
	var m: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence/furnished_world/manifest.json"))
	var origin:=Vector3(m.target[0],m.target[1],m.target[2]);var routes: Array=[]
	for street in range(2):
		var road: Dictionary=game.road_palette.prepared_streets[street]
		for side in range(2):
			var room:=Transform3D(Basis(Vector3.UP,side*PI),Vector3(origin.x+4.5,origin.y+2,road.ends[0].z+(-13.5 if side==0 else 13.5)))
			if "--repair-entrances" in OS.get_cmdline_user_args():
				var cells:=PackedInt32Array()
				for x in [-1.0,0.0,1.0]:
					for z in [6.0,7.0]:
						var cell:=Vector3i((room*Vector3(x,-1.5,z)).floor())
						var word: int=65 if z==6.0 else 3+(((2+side*2)%4)<<3)+64
						cells.append_array(PackedInt32Array([cell.x,cell.y,cell.z,word]))
				check(game.structures.blocks.set_cells(cells),"repair lower entrance stairs")
			game.player.global_position=room*Vector3(0,-1.9,9)
			game.player.rotation.y=side*PI;game.yaw=side*PI;game.pitch=-0.12;game.camera.rotation=Vector3(game.pitch,0,0)
			game.terrain.focus=game.player.position;game.player.velocity=Vector3.ZERO
			for frame in range(90):await physics_frame
			game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
			var start: Vector3=game.player.position;var path: Array=[]
			game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
			for frame in range(180):
				await physics_frame
				game._physics_process(1.0/60.0)
				if frame%15==0:path.append({"position":game.player.position,"blocked":game.structure_motion_blocked,"loading":game.loading_active,"on_floor":game.player.is_on_floor()})
				if (room.affine_inverse()*game.player.position).z<2.5:break
			game.controls.clear(Time.get_ticks_usec())
			var local: Vector3=room.affine_inverse()*game.player.position
			check(local.z<2.5 and absf(local.y)<0.2,"walk from approach into cottage %d/%d without jumping"%[street,side])
			routes.append({"street":street,"side":side,"start":start,"finish":game.player.position,"local_finish":local,"path":path})
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://reports/settlement_walk")
			root.get_texture().get_image().save_png("res://reports/settlement_walk/%d_%d.png"%[street,side])
	if "--repair-entrances" in OS.get_cmdline_user_args():
		var snapshot:=FileAccess.open(DIR+"blocks.bin",FileAccess.WRITE)
		snapshot.store_buffer(game.structures.blocks.capture_snapshot());snapshot.close()
	game.player.position=Vector3(origin.x+4.5,origin.y+2.1,game.road_palette.prepared_streets[0].ends[0].z-10.0)
	game.yaw=0.0;game.player.rotation.y=0.0
	var file:=FileAccess.open("res://reports/settlement_walk/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"routes":routes},"  "));file.close()
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)
