extends SceneTree
const Stream = preload("res://addons/volumetric_terrain/terrain_stream.gd")
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")

class FixedCut extends Stream:
	# Isolate publication from the quadtree's whole-world coverage requirement.
	func _update_cut() -> void:
		pass

var world: Stream
var core: RefCounted
var recipes: RefCounted
var checks: Array[Dictionary] = []
var failures := 0
var timings: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks.append({"pass":ok,"name":label})
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func build(key: Vector3i, stamp: int) -> Dictionary:
	var start := Time.get_ticks_usec()
	var reply: PackedByteArray = core.execute(Codec.command(1,[key.x,key.y,key.z,1]))
	assert(Codec.reply_ok(reply))
	var data: Dictionary = Codec.decode_mesh(reply.slice(16))
	assert(not data.has("error"))
	var prepared: Dictionary = recipes.prepare(data.faces,1024)
	data.merge({"kind":"mesh","epoch":world.epoch,"stamp":stamp,"worker_ms":0.0,"collision_pieces":prepared.pieces})
	timings.append({"stage":"build_decode_recipes","ms":(Time.get_ticks_usec()-start)/1000.0})
	return data

func drain() -> void:
	var start := Time.get_ticks_usec()
	var calls := 0
	while not world.staging.is_empty() or not world.preparation.is_empty():
		world._drain_staging()
		calls += 1
		assert(calls<1000)
	timings.append({"stage":"drain_staging","ms":(Time.get_ticks_usec()-start)/1000.0,"calls":calls})

func physics_hits(entries: Dictionary, label: String) -> Array[float]:
	# physics_frame fires before simulation; observe after it has processed updates.
	await physics_frame
	await process_frame
	var heights: Array[float] = []
	for key in world.visible_cut:
		var x: float = 1295.0 if key.x==1280 else 1297.0
		var z: float = 1295.0 if key.y==1280 else 1297.0
		var query := PhysicsRayQueryParameters3D.create(Vector3(x,300,z),Vector3(x,0,z),1)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		var matches: bool=not hit.is_empty() and hit.get("collider")==entries[key].body
		if entries[key].has("bricks"):
			for child: Dictionary in entries[key].bricks.values(): matches=matches or (not hit.is_empty() and hit.get("collider")==child.body)
		check(matches,label+" %s" % key)
		heights.append(float(hit.position.y) if not hit.is_empty() else -1.0)
	return heights

func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	core = ClassDB.instantiate("TerrainCore")
	recipes = ClassDB.instantiate("NativeTerrainCollision")
	world = FixedCut.new()
	root.add_child(world)
	world.set_process(false)
	world.material = StandardMaterial3D.new()
	for z in [1280,1296]:
		for x in [1280,1296]: world.visible_cut.append(Vector3i(x,z,16))
	var originals: Dictionary = {}
	for key in world.visible_cut:
		world._receive(build(key,0))
		drain()
		originals[key] = world.tiles[key]
	check(world.tiles.size()==4,"four native fine regions installed")
	for key in world.visible_cut:
		check(originals[key].node.visible and originals[key].body.collision_layer==1,"initial visual and collider active %s" % key)
	var old_heights: Array[float] = await physics_hits(originals,"physics ray sees original collider")
	# An obsolete reply must not clear a newer in-flight request or enter staging.
	var first: Vector3i = world.visible_cut[0]
	world.stamps[first] = 1
	world.in_flight[first] = Vector2i(world.epoch,1)
	world._receive({"kind":"mesh","key":first,"epoch":world.epoch,"stamp":0})
	world._receive({"kind":"mesh","key":first,"epoch":world.epoch-1,"stamp":1})
	check(world.staging.is_empty() and world.in_flight[first]==Vector2i(world.epoch,1),"obsolete stamp and epoch preserve newer request")
	# Invalidate after upload starts but before collision preparation completes.
	var stale := build(first,1)
	var abandoned: Dictionary = world._begin_entry(stale)
	world.preparation = {"data":stale,"entry":abandoned,"piece_at":0}
	world.stamps[first] = 2
	drain()
	check(world.tiles[first]==originals[first] and not abandoned.node.visible and abandoned.body.collision_layer==0,"stale preparation cannot replace live visual or collision")
	var point := Vector3(1296,0,1296)
	point.y = core.execute(Codec.point_command(point)).decode_float(12)
	var edit: PackedByteArray = core.execute(Codec.brush(point,point,4,0,false,1))
	check(Codec.reply_ok(edit) and edit.decode_u32(16)>0,"boundary excavation changes native field")
	world.pending_edit = true
	world.edit_ticket = 3
	world.edit_started_us = Time.get_ticks_usec()
	world.batch_remaining = 4
	world.geometry_lo = point-Vector3.ONE*9
	world.geometry_hi = point+Vector3.ONE*9
	var changed := 0
	for key in world.visible_cut:
		world.stamps[key] = 3
		var data := build(key,3)
		if data.arrays[Mesh.ARRAY_VERTEX] != originals[key].arrays[Mesh.ARRAY_VERTEX]: changed += 1
		data.kind = "edit_chunk"
		data.ticket = 3
		world._receive(data)
		drain()
		var untouched := true
		for old_key in originals:
			untouched = untouched and world.tiles[old_key]==originals[old_key] and originals[old_key].node.visible and originals[old_key].body.collision_layer==1
		check(untouched,"old complete batch stays active during preparation %s" % key)
	check(changed==4,"excavation changes all four neighboring meshes")
	check(world.batch_remaining==0 and world.staged_batch.size()==4 and world.pending_edit,"prepared batch waits for worker completion")
	var held_heights: Array[float] = await physics_hits(originals,"prepared replacement remains absent from physics queries")
	check(old_heights==held_heights,"physics surface remains unchanged before commit")
	world._receive({"kind":"edit_done","epoch":world.epoch,"ticket":2})
	check(world.pending_edit and world.staged_batch.size()==4,"obsolete completion cannot publish batch")
	world._receive({"kind":"edit_done","epoch":world.epoch,"ticket":3,"build_total_ms":0.0,"worker_finished_us":Time.get_ticks_usec()})
	check(not world.pending_edit and world.published_revision==1 and world.staged_batch.is_empty(),"matching completion publishes once")
	world._receive({"kind":"edit_done","epoch":world.epoch,"ticket":3,"build_total_ms":0.0,"worker_finished_us":Time.get_ticks_usec()})
	check(world.published_revision==1,"duplicate completion cannot republish the finished transaction")
	for key in world.visible_cut:
		var current: Dictionary = world.tiles[key]
		check(current.stamp==3 and current.node.visible and current.body.collision_layer==1 and not originals[key].node.visible and originals[key].body.collision_layer==0,"visual and collision activation switch together %s" % key)
	var new_heights: Array[float] = await physics_hits(world.tiles,"physics ray sees replacement collider")
	var lower_hits := 0
	for i in range(4):
		if new_heights[i]<old_heights[i]-0.01: lower_hits += 1
	check(lower_hits==4,"all four physics rays observe the excavated surface")
	world.shutdown()
	world.free()
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/terrain_publication_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"checks":checks,"timings":timings,"old_ray_heights":old_heights,"new_ray_heights":new_heights,"scope":"Headless existing-stream publication with four native 16 m fixtures, fixed visible cut and physics-step ray queries. No worker scheduling, quadtree transitions, draw/GPU, new mesher, endurance or FPS qualification."},"  "))
	file.close()
	quit(0 if failures==0 else 1)
