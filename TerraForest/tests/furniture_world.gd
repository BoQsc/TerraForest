# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var reopen: bool="--reopen-furniture" in OS.get_cmdline_user_args()
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"main world ready")
	game.set_physics_process(false);game._clear_motion();game.app_focused=true
	check(game.model_tool.catalog.size()==6,"all furniture available through normal object catalog")
	var base: Vector3=game.player.position.snapped(Vector3.ONE)+Vector3.UP*12
	var dir:="res://reports/furniture/"
	DirAccess.make_dir_recursive_absolute(dir)
	if reopen:
		var data: Dictionary=FileAccess.open(dir+"fixture.bin",FileAccess.READ).get_var()
		base=data.base
		check(game.structures.restore_storage_snapshot(data.structures),"fresh process restores combined block and furniture snapshot")
		check(game.structures.capture_storage_snapshot()==data.structures,"exact authoritative snapshot survives fresh process")
	else:
		var cells:=PackedInt32Array()
		for x in range(-6,7):
			for z in range(-6,3): cells.append_array(PackedInt32Array([int(base.x)+x,int(base.y)-1,int(base.z)+z,1]))
		check(game.structures.blocks.set_cells(cells),"real editable block floor supports interior fixture")
	game.player.position=base+Vector3(0,0.1,1);game.needs_floor_spawn=false;game.fly=true
	for frame in range(60): await physics_frame
	game._set_player_tool_mode(true,true,game.tool);game.model_tool.edit_available=true
	if not reopen:
		for i in range(3):
			game.model_tool.select(3+i)
			game.camera.global_position=base+Vector3(i*2-2,2,1)
			game.camera.look_at(base+Vector3(i*2-2,0,-2))
			check(game.model_tool.edit(false)>0,"normal paid object tool places "+game.model_tool.catalog[3+i].title)
		var file:=FileAccess.open(dir+"fixture.bin",FileAccess.WRITE)
		file.store_var({"base":base,"structures":game.structures.capture_storage_snapshot()});file.close()
	for frame in range(30): await physics_frame
	for i in range(3):
		var entry: Dictionary=game.model_tool.catalog[3+i]
		check(entry.collection.get_ids().size()==1,"one durable identity for "+entry.title)
		check(entry.collection.render_stats().resident_instances==1,"native render residency for "+entry.title)
		var point:=base+Vector3(i*2-2,0,-2)
		var hit: Dictionary=game.structures.blocks.raycast_scene(point+Vector3.UP*3,point,2,[])
		check(not hit.is_empty() and hit.collider==entry.collection,"native compound collider matches "+entry.title)
	# Empty space beneath the table remains traversable by rays, not a solid AABB.
	var table: Vector3=base+Vector3(-2,0.3,-2)
	check(game.structures.blocks.raycast_scene(table+Vector3(0,0,-1),table+Vector3(0,0,1),2,[]).is_empty(),"table leg gap is not filled by a bounding-box collider")
	game.camera.global_position=base+Vector3(4,3,4);game.camera.look_at(base+Vector3(0,0.6,-2))
	game.model_tool.select(3);game.model_tool.update(0,true)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir+("reopen.png" if reopen else "placed.png"))
	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample and Engine.max_fps==60,"1080p fullscreen cap60")
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"world drains normally")
	game.free();await process_frame;await process_frame
	print("FURNITURE_WORLD failures=",failures);quit(1 if failures else 0)
