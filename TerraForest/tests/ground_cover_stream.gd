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
	func request_surface_batch(points: PackedVector3Array,token: int) -> bool:
		requests.append({"points":points,"token":token});return true
	func request_density_batch(points: PackedVector3Array,token: int) -> bool:
		density_requests.append({"points":points,"token":token});return true
	func reply_density() -> void:
		var request: Dictionary=density_requests.pop_front()
		var values:=PackedFloat32Array()
		for i in range(request.points.size()): values.append(-1.0 if i%2==0 else 1.0)
		density_batch_ready.emit({"token":request.token,"epoch":epoch,"revision":density_revision,"status":"ok","values":values})
	func reply() -> void:
		var request: Dictionary=requests.pop_front()
		var normals:=PackedVector3Array();normals.resize(request.points.size());normals.fill(Vector3.UP)
		surface_batch_ready.emit(request.token,request.points,normals,epoch,published_revision)
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
	check(cover.batches.size()==3,"three native species render collections initialized")
	for i in range(49):
		cover._process(0.0)
		check(terrain.requests.size()==1,"one outstanding support batch %d"%i)
		terrain.reply();finish_support(cover,terrain)
	check(cover.resident.size()==49 and cover.rejected_batches==0,"49 owners publish without rejection")
	var count:=0
	for batch in cover.batches:
		count+=batch.get_ids().size()
		check(not batch.collision_stats().enabled and batch.collision_stats().resident_bodies==0,"ground cover creates no physics bodies")
	check(count==3136,"bounded 3136 individual candidates resident")
	var key:=Vector2i(30,30)
	var row: Dictionary=cover.resident[key][2]
	var removed_id: int=row.ids[0]
	check(cover.removed.mark(removed_id),"individual removal persists separately from rendering")
	var authored_id: int=cover.removed.add(0,Transform3D(Basis.IDENTITY,Vector3(970,20,970)))
	check(authored_id>0,"authored stone gets independent durable identity")
	cover._exclusion_changed(AABB(Vector3(976,-1,976),Vector3(1,2,1)))
	check(cover._dirty.size()==1,"small interior disturbance invalidates one owner")
	cover._process(0.0);terrain.reply();finish_support(cover,terrain)
	check(not cover.batches[2].get_ids().has(removed_id) and cover.resident.size()==49,"individual removal preserves neighbour owners")
	check(cover.batches[0].get_ids().has(authored_id),"authored placement joins native rendering for its owner")
	check(cover.picker.pick(Vector3(970,20.1,970),Vector3(970,21,970)).get("id",0)==authored_id,"render publication also publishes individual interaction identity")
	cover._dirty[key]=true
	cover._process(0.0);terrain.reply()
	check(not cover._support_job.is_empty(),"authored owner enters bounded asynchronous support stage")
	cover._process(0.0);cover._process(0.0)
	check(terrain.density_requests.size()==1,"support stage admits only one outstanding density request")
	terrain.density_revision+=1;terrain.reply_density()
	check(cover._support_job.is_empty() and cover._dirty.has(key),"stale density reply cannot finalize edited owner")
	cover._process(0.0);terrain.reply();finish_support(cover,terrain)
	check(not cover._dirty.has(key) and cover.batches[0].get_ids().has(authored_id),"fresh support retry preserves authored identity")
	camera.position=Vector3(1600,3,1600);cover._process(0.0)
	check(cover.resident.is_empty() and terrain.requests.size()==1,"teleport retires old owners and submits one destination batch")
	check(not cover.picker.pick(Vector3(970,20.1,970),Vector3(970,21,970)).hit,"unloaded owner leaves no stale interaction proxy")
	camera.position=Vector3(960,3,960);cover._process(0.0)
	check(terrain.requests.size()==1,"teleport does not multiply outstanding jobs")
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
	cover.reset()
	check(cover.resident.is_empty() and cover.batches[0].get_ids().is_empty() and cover.batches[1].get_ids().is_empty() and cover.batches[2].get_ids().is_empty(),"reset releases generated records")
	cover.free();terrain.free();camera.free()
	print("GROUND_COVER_STREAM ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)

func finish_support(cover: Node,terrain: Node) -> void:
	if not cover._support_job.is_empty():
		cover._process(0.0);terrain.reply_density()
