# SPDX-License-Identifier: 0BSD
extends SceneTree
class Terrain extends Node3D:
	signal surface_batch_ready(token,points,normals,epoch,revision)
	signal region_changed(bounds,revision)
	signal density_batch_ready(result)
	signal reload_started
	var world_ready:=true
	var stopping:=false
	var pending_edit:=false
	var epoch:=1
	var density_revision:=0
	var density_requests: Array=[]
	var published_revision:=0
	var requests: Array=[]
	var admission_limit:=4
	var reverse_replies:=false
	func request_surface_batch(points: PackedVector3Array,token: int) -> bool:
		if requests.size()>=admission_limit:return false
		requests.append({"points":points,"token":token});return true
	func request_interpolated_density_batch(points: PackedVector3Array,token: int) -> bool:
		density_requests.append({"points":points,"token":token});return true
	func reply_density() -> void:
		var request: Dictionary=density_requests.pop_front()
		var values:=PackedFloat32Array()
		for i in range(request.points.size()): values.append(-1.0 if i%2==0 else 1.0)
		density_batch_ready.emit({"token":request.token,"epoch":epoch,"revision":density_revision,"status":"ok","values":values})
	func reply_one() -> void:
		var request: Dictionary=requests.pop_back() if reverse_replies else requests.pop_front()
		var normals:=PackedVector3Array();normals.resize(request.points.size());normals.fill(Vector3.UP)
		surface_batch_ready.emit(request.token,request.points,normals,epoch,published_revision)
	func reply() -> void:
		while not requests.is_empty():reply_one()

var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var terrain:=Terrain.new();root.add_child(terrain)
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(960,3,960)
	var cover=load("res://addons/world_ecosystem/ground_cover.gd").new()
	cover.terrain=terrain;cover.camera=camera
	var persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	check(cover.prepare(persistence),"removal provider registers with world persistence")
	root.add_child(cover);cover.set_process(false)
	check(cover.grass_texture_enabled and cover.grass_material.get_shader_parameter("grass_detail_strength")==0.8,"accepted grass texture enabled in world coordinator")
	var initial: PackedByteArray=cover.removed.capture_storage_snapshot()
	check(cover.set_grass_texture(false) and not cover.grass_texture_enabled and cover.set_grass_texture(true) and cover.removed.capture_storage_snapshot()==initial,"texture toggle preserves world records")
	check(cover.batches.size()==9,"nine native species render collections initialized")
	for i in range(81):
		cover._process(0.0)
		check(terrain.requests.size()==4,"four bounded support jobs %d"%i)
		terrain.reply();finish_support(cover,terrain)
	check(cover.resident.size()==81 and cover.rejected_batches==0,"81 owners publish without rejection")
	var count:=0
	for batch in cover.batches:
		count+=batch.get_ids().size()
		check(not batch.collision_stats().enabled and batch.collision_stats().resident_bodies==0,"ground cover creates no physics bodies")
	check(count==82944,"bounded 82944 candidates maintain density through all 81 owners")
	var key:=Vector2i(30,30)
	var row: Dictionary=cover.resident[key][2]
	var removed_id: int=row.ids[0]
	check(cover.removed.mark(removed_id),"individual removal persists separately from rendering")
	var authored_id: int=cover.removed.add(0,Transform3D(Basis.IDENTITY,Vector3(970,20,970)))
	check(authored_id>0,"authored stone gets independent durable identity")
	cover._exclusion_changed(AABB(Vector3(976,-1,976),Vector3(1,2,1)))
	check(cover._dirty.size()==1,"small interior disturbance invalidates one owner")
	cover._process(0.0);terrain.reply();finish_support(cover,terrain)
	check(not cover.batches[2].get_ids().has(removed_id) and cover.resident.size()==81,"individual removal preserves neighbour owners")
	check(cover.batches[0].get_ids().has(authored_id),"authored placement joins native rendering for its owner")
	check(cover.picker.pick(Vector3(970,20.1,970),Vector3(970,21,970)).get("id",0)==authored_id,"render publication also publishes individual interaction identity")
	cover._dirty[key]=true
	cover._process(0.0);terrain.reply();finish_natural(cover,terrain)
	check(not cover._support_job.is_empty(),"authored owner enters bounded asynchronous support stage")
	cover._process(0.0);cover._process(0.0)
	check(terrain.density_requests.size()==1,"support stage admits only one outstanding density request")
	terrain.density_revision+=1;terrain.reply_density()
	check(cover._support_job.is_empty() and cover._dirty.has(key),"stale density reply cannot finalize edited owner")
	cover._process(0.0);terrain.reply();finish_support(cover,terrain)
	check(not cover._dirty.has(key) and cover.batches[0].get_ids().has(authored_id),"fresh support retry preserves authored identity")
	camera.position=Vector3(1600,3,1600);cover._process(0.0)
	check(cover.resident.is_empty() and terrain.requests.size()==4,"teleport retires old owners and submits four destination jobs")
	check(not cover.picker.pick(Vector3(970,20.1,970),Vector3(970,21,970)).hit,"unloaded owner leaves no stale interaction proxy")
	camera.position=Vector3(960,3,960);cover._process(0.0)
	check(terrain.requests.size()==4,"teleport preserves the four-job bound")
	terrain.reply();finish_support(cover,terrain)
	check(cover.resident.is_empty(),"obsolete destination reply does not publish")
	cover._process(0.0);terrain.reply();finish_support(cover,terrain)
	check(cover.resident.size()==1 and not cover.batches[2].get_ids().has(removed_id) and cover.batches[0].get_ids().has(authored_id),"return regeneration retains individual removal and authored placement")
	check(cover.picker.pick(Vector3(970,20.1,970),Vector3(970,21,970)).get("id",0)==authored_id,"return restores same authored interaction identity")
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var interaction=load("res://addons/world_ecosystem/ground_interaction.gd").new()
	interaction.cover=cover
	var inventory=ClassDB.instantiate("NativePlayerInventory")
	inventory.register_item(201,999);inventory.register_item(204,999);inventory.register_item(205,999)
	interaction.scene_ray=func(_from,_to):return {"position":Vector3(970,21,970),"normal":Vector3.UP}
	check(not interaction.collect(Vector3(970,22,970),Vector3(970,18,970),inventory,true).ok and cover.batches[0].get_ids().has(authored_id),"scene obstruction prevents collection through geometry")
	interaction.scene_ray=func(_from,_to):return {}
	var rejected_inventory=ClassDB.instantiate("NativePlayerInventory")
	check(not interaction.collect(Vector3(970,22,970),Vector3(970,18,970),rejected_inventory,true).ok and cover.batches[0].get_ids().has(authored_id),"rejected inventory grant preserves authored object")
	check(interaction.collect(Vector3(970,22,970),Vector3(970,18,970),inventory,true).ok and not cover.batches[0].get_ids().has(authored_id) and cover.removed.profile().placed==0,"collection immediately removes authored render query and durable record")
	check(inventory.can_afford(PackedInt64Array([201,1]),inventory.snapshot().revision).ok and not interaction.collect(Vector3(970,22,970),Vector3(970,18,970),inventory,true).ok,"collection grants exactly one stone and cannot repeat")
	interaction.scene_ray=func(_from,_to):return {"position":Vector3(974,20,974),"normal":Vector3.UP}
	var placement: Dictionary=interaction.place(0,Vector3(974,22,974),Vector3(974,18,974),inventory,true)
	check(placement.ok and not inventory.can_afford(PackedInt64Array([201,1]),inventory.snapshot().revision).ok,"gameplay placement consumes collected stone")
	cover._process(0.0);terrain.reply();finish_support(cover,terrain)
	check(cover.batches[0].get_ids().has(placement.get("id",0)),"placed stone reaches rendering through support publication")
	check(not interaction.place(0,Vector3(974,22,974),Vector3(974,18,974),inventory,true).ok,"occupied spot rejects duplicate placement")
	interaction.scene_ray=func(_from,_to):return {"position":Vector3(978,20,978),"normal":Vector3.UP}
	check(not interaction.place(1,Vector3(978,22,978),Vector3(978,18,978),inventory,true).ok,"gameplay placement refuses missing plant item")
	var before_inventory: PackedByteArray=inventory.capture_storage_snapshot()
	check(interaction.place(1,Vector3(978,22,978),Vector3(978,18,978),inventory,false).ok and inventory.capture_storage_snapshot()==before_inventory,"editor placement stays free")
	cover._process(0.0);terrain.reply();finish_support(cover,terrain)
	interaction.scene_ray=func(_from,_to):return {}
	check(interaction.collect(Vector3(978,22,978),Vector3(978,18,978),inventory,false).ok and inventory.capture_storage_snapshot()==before_inventory,"editor removal stays free and grants no gameplay resources")
	camera.position+=Vector3(32,0,0)
	for i in 100:
		cover._process(0.0)
		if not terrain.requests.is_empty():terrain.reply();finish_support(cover,terrain)
		if cover.resident.size()==81 and cover._dirty.is_empty() and cover._scatter_job.is_empty():break
	var bands_ok:bool=cover.resident.size()==81 and cover._dirty.is_empty()
	for owner:Vector2i in cover.resident:bands_ok=bands_ok and cover._resident_layers[owner]==cover._layers(owner)
	check(bands_ok and cover.rejected_batches==0,"crossing a cell boundary upgrades nearby cover and retains loaded layers until owner retirement")
	# A world invalidation can mark owners dirty before their first publication.
	# Leaving during that load must retire those requests as well as resident cells.
	cover.reset();camera.position=Vector3(960,3,960);cover._process(0.0)
	cover._exclusion_changed(AABB())
	camera.position=Vector3(1600,3,1600);cover._process(0.0)
	var dirty_current:=true
	for owner:Vector2i in cover._dirty:dirty_current=dirty_current and cover._wanted.has(owner)
	check(dirty_current,"teleport retires dirty owners that never published")
	terrain.reply();finish_support(cover,terrain)
	cover.reset();camera.position=Vector3(960,3,960)
	cover._process(0.0);terrain.reply();finish_support(cover,terrain)
	var reference:Array=cover.resident[Vector2i(30,30)].duplicate(true)
	cover.reset();terrain.admission_limit=2;terrain.reverse_replies=true
	cover._process(0.0)
	check(terrain.requests.size()==2,"partial admission accepts only two jobs without advancing rejected layers")
	terrain.reply();finish_support(cover,terrain)
	check(cover.resident.get(Vector2i(30,30),[])==reference,"partial admission and reversed replies reproduce identical ordered records")
	cover.reset();terrain.admission_limit=4
	cover._process(0.0)
	var bad:Dictionary=terrain.requests.pop_front()
	terrain.surface_batch_ready.emit(bad.token,PackedVector3Array(),PackedVector3Array(),terrain.epoch,terrain.published_revision)
	terrain.reply()
	check(cover._requests.is_empty() and cover._scatter_job.is_empty() and cover.resident.is_empty(),"malformed reply abandons wave without publishing partial owner or stranding requests")
	cover._process(0.0);terrain.reply();finish_support(cover,terrain)
	check(cover.resident.get(Vector2i(30,30),[])==reference,"retry after failed wave restores exact records")
	var saved_edits:PackedByteArray=cover.removed.capture_storage_snapshot()
	cover._begin_reset()
	var hidden:=true
	for batch in cover.batches:hidden=hidden and not batch.visible
	check(hidden,"staged reset hides every old vegetation batch immediately")
	var reset_steps:=0;var status:=0
	while status==0 and reset_steps<128:
		status=cover._advance_reset(1);reset_steps+=1
	check(status==1 and reset_steps>1 and not cover._reset_active,"staged reset completes through bounded preparation steps")
	check(cover.removed.capture_storage_snapshot()==saved_edits,"runtime reset preserves saved vegetation edits")
	check(cover.resident.is_empty() and cover.batches[0].get_ids().is_empty() and cover.batches[1].get_ids().is_empty() and cover.batches[2].get_ids().is_empty(),"reset releases generated records")
	cover._process(0.0);terrain.reply();finish_support(cover,terrain)
	check(cover.resident.get(Vector2i(30,30),[])==reference,"staged reset regenerates exactly the same vegetation records")
	cover.free();terrain.free();camera.free()
	print("GROUND_COVER_STREAM ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)

func finish_natural(cover:Node,terrain:Node)->void:
	for i in 16:
		if cover._scatter_job.is_empty():break
		cover._process(0.0)
		if terrain.requests.is_empty():break
		terrain.reply()

func finish_support(cover: Node,terrain: Node) -> void:
	finish_natural(cover,terrain)
	if not cover._support_job.is_empty():
		cover._process(0.0);terrain.reply_density()
