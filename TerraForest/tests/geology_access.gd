# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const DIR="res://reports/geology_access/"
var failures:=0
var routes: Array=[]
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,4]))
	for pair in [[8,Vector3(364,113,368)],[9,Vector3(368,109,332)]]:
		var point: Vector3=pair[1];var a:=point-Vector3(40,0,0)
		var height: PackedByteArray=core.execute(Codec.point_command(a));a.y=height.decode_float(12)+3
		routes.append({"material":pair[0],"ore":point,"a":a,"b":point-Vector3(2.5,0,0)})
	core=null
	var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"editor world ready")
	game.set_physics_process(false);game._clear_motion();game.fly=true;game.needs_floor_spawn=false
	check(not game.headlamp.visible,"headlamp defaults off")
	var key:=InputEventKey.new();key.physical_keycode=KEY_F;key.pressed=true
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;game._unhandled_input(key)
	check(game.headlamp.visible and game.headlamp.shadow_enabled and game.headlamp.spot_range==14,"F enables bounded shadowed headlamp")
	game.player_hud.set_open(true);game._unhandled_input(key);check(game.headlamp.visible,"inventory modal consumes headlamp input");game.player_hud.set_open(false)
	game.app_focused=false;game._unhandled_input(key);check(game.headlamp.visible,"unfocused input cannot toggle headlamp")
	var reopen: bool="--reopen-access" in OS.get_cmdline_user_args()
	for route: Dictionary in routes:
		game.player.position=route.a;game.terrain.focus=game.player.position
		if not reopen:
			check(game.terrain.edit(Codec.brush(route.a,route.b,2.5,0,false,1),route.a.min(route.b),route.a.max(route.b)),"excavate access tunnel %d"%route.material)
			deadline=Time.get_ticks_msec()+30000
			while game.terrain.pending_edit and Time.get_ticks_msec()<deadline:await process_frame
			check(not game.terrain.pending_edit,"access tunnel publishes")
		game.player.position=route.a-Vector3(0,1.5,0);game.player.velocity=Vector3.ZERO
		game.yaw=-PI/2;game.player.rotation.y=game.yaw;game.pitch=0;game.camera.rotation=Vector3.ZERO;game.fly=false
		for frame in 90:await physics_frame
		game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
		var began:=Time.get_ticks_msec();var path: Array=[]
		for frame in 720:
			await physics_frame;game._physics_process(1.0/60.0)
			if frame%30==0:path.append({"position":game.player.position,"blocked":game.structure_motion_blocked,"on_floor":game.player.is_on_floor()})
			if game.player.position.x>route.b.x-2:break
		game.controls.clear(Time.get_ticks_usec())
		route.finish=game.player.position;route.path=path;route.walk_ms=Time.get_ticks_msec()-began
		check(game.player.position.x>route.b.x-2 and game.player.is_on_floor(),"walk surface approach to ore face %d without jumping"%route.material)
		game.camera.look_at(route.ore)
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(DIR+"ore_%d.png"%route.material)
	game.player.position=routes[0].a+Vector3(0,1,0);game.player.velocity=Vector3.ZERO;game.fly=false
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"save accessible geology checkpoint")
	var file:=FileAccess.open(DIR+"result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"routes":routes,"slot":game.terrain.save_slot,"scope":"Authored access tunnels to seeded ore, actual player controls and headlamp at fullscreen1080p cap60; no natural-cave discovery or performance claim."},"  "));file.close()
	game.free();await process_frame;quit(1 if failures else 0)
