# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	game.terrain.backend.disable_snapshot_writes()
	check(not game.loading_active and not game.road_palette.prepared_streets.is_empty(),"saved settlement ready")
	if game.loading_active or game.road_palette.prepared_streets.is_empty():game.terrain.shutdown();game.free();quit(1);return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true
	var ends: PackedVector3Array=game.road_palette.prepared_streets[0].ends
	var direction: Vector3=(ends[1]-ends[0]).normalized();var side:=Vector3(-direction.z,0,direction.x)
	var start: Vector3=ends[0]+direction*5+Vector3.UP*0.95
	game.player.position=start-direction*8;game.terrain.focus=start
	game.camera.global_position=start-direction*8+side*6+Vector3.UP*5;game.camera.look_at(start+direction*6)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var bounds:=AABB(start-Vector3.ONE*3,Vector3.ONE*6).expand(start+direction*15)
	deadline=Time.get_ticks_msec()+15000
	while not game.world_vehicle.ready_bounds(game,bounds) and Time.get_ticks_msec()<deadline:await process_frame
	check(game.world_vehicle.ready_bounds(game,bounds),"route terrain structures and tree collision ready")
	var store: RefCounted=ClassDB.instantiate("NativeEntityStore");store.configure(100010)
	store.spawn_grid(100000,Vector3(10000,0,10000),2,Vector3.ZERO)
	var actors: Array=[];var ids:=PackedInt64Array();var initial:=PackedVector3Array()
	for i in 4:
		var position:=start+side*(i-1.5)*1.2
		var id: int=store.spawn(position,Vector3.ZERO);ids.append(id);initial.append(position)
		var actor: CharacterBody3D=ClassDB.instantiate("NativeEntityActor");actor.collision_layer=2;actor.collision_mask=1;actor.floor_snap_length=0.25
		var collision:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=0.35;capsule.height=1.8;collision.shape=capsule;actor.add_child(collision);game.add_child(actor)
		check(actor.bind_entity(store,id),"actor binds "+str(i));actors.append(actor)
	var renderer: MultiMeshInstance3D=ClassDB.instantiate("NativeEntityRenderer");game.add_child(renderer)
	var mesh:=CapsuleMesh.new();mesh.radius=0.35;mesh.height=1.8
	var material:=StandardMaterial3D.new();material.albedo_color=Color("edb35a");mesh.material=material
	check(renderer.configure(store,mesh,16),"native batched actor rendering configured")
	var rows: Array=[];var held:=0;var supported:=0
	for tick in 180:
		await physics_frame
		for i in actors.size():
			var actor: CharacterBody3D=actors[i]
			var envelope:=AABB(actor.global_position-Vector3(0.6,1.3,0.6),Vector3(1.2,2.6,1.2)).grow(actor.velocity.length()/60.0)
			var ready: bool=game.world_vehicle.ready_bounds(game,envelope)
			if not ready:held+=1
			actor.tick(initial[i]+direction*12,1.0/60,ready)
			if actor.is_on_floor():supported+=1
		var rendered: Dictionary=renderer.refresh(start,32,4096)
		rows.append({"tick":tick,"rendered":rendered.rendered,"visited":rendered.visited,"supported":supported,"held":held})
	var positions:=PackedVector3Array()
	for i in actors.size():
		positions.append(actors[i].position)
		check((actors[i].position-initial[i]).dot(direction)>6 and absf(actors[i].position.y-initial[i].y)<0.5,"actor travels on saved road without falling "+str(i))
	check(held==0 and supported>=700,"loaded road sustains support without readiness holds")
	check(rows[-1].rendered==4 and rows[-1].visited<=8,"native renderer selects four local actors from 100004 records")
	check(store.statistics().moving==0,"collision proxies own integration; distant records stay asleep")
	var snapshot: PackedByteArray=store.capture_storage_snapshot()
	var copy: RefCounted=ClassDB.instantiate("NativeEntityStore");copy.configure(100010)
	check(copy.restore_storage_snapshot(snapshot) and copy.capture_storage_snapshot()==snapshot,"corrected actor records round-trip exactly")
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://reports/entity_actor_world")
	root.get_texture().get_image().save_png("res://reports/entity_actor_world/world.png")
	var file:=FileAccess.open("res://reports/entity_actor_world/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"held":held,"supported":supported,"positions":positions,"rows":rows},"  "));file.close()
	game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
