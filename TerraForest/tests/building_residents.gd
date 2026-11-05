# SPDX-License-Identifier: 0BSD
extends SceneTree
const Homes=preload("res://addons/characters/runtime/house_sleepers.gd")
var checks:=0
var failures:=0
var folder:="res://reports/building_residents"
var all_anchors:Array=[]
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label);return ok
func frames(count:int=3)->void:
	for frame in count:await physics_frame
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--building-output="):folder=arg.trim_prefix("--building-output=")
	run.call_deferred()
func run()->void:
	DirAccess.make_dir_recursive_absolute(folder)
	var store=ClassDB.instantiate("NativeZombiePopulation");store.initialize(1703,Vector3(1800,0,1800))
	if "--restore-building-residents" in OS.get_cmdline_user_args():
		var bytes:=FileAccess.get_file_as_bytes(folder.path_join("population.bin"))
		var receipt:Dictionary=FileAccess.open(folder.path_join("population.meta"),FileAccess.READ).get_var()
		check(store.restore_snapshot(bytes),"fresh process restores building resident snapshot")
		var replay:Dictionary=store.register_sleepers(receipt.anchors)
		check(replay.ok and replay.added==0 and store.capture_snapshot()==bytes,"fresh-process republication cannot duplicate or refill cleared residents")
		check(store.resident(receipt.dead).state==2,"cleared building resident remains dead in fresh process")
		finish();return
	for id:String in Homes.LARGE:
		for turn in 4:
			var stage:=Node3D.new();root.add_child(stage)
			var structures=preload("res://addons/structures/structures_world.gd").new();stage.add_child(structures);structures.prepare()
			for catalog:String in ["furniture","ladder","storage","window","door","guardrail","fence"]:load("res://addons/structures/"+catalog+"_catalog.gd").register(structures)
			var asset:Resource=Homes.Catalog.asset(id) if Homes.Catalog.IDS.has(id) else Homes.City.asset(Homes.City.IDS.find(id))
			var origin:=Vector3i(100+Homes.LARGE.keys().find(id)*120,20,100)
			var plan:Dictionary=Homes.plan([{"asset":asset,"origin":origin,"rotation":turn}],1703)
			if not check(plan.ok and plan.anchors.size()==Homes.LARGE[id].size(),"minimum group planned: %s turn %d"%[id,turn]):stage.free();continue
			all_anchors.append_array(plan.anchors)
			var placement=ClassDB.instantiate("NativePrefabPlacement")
			if not check(placement.place(structures.blocks,asset,origin,turn,structures.model_collections(),[]).get("ok",false),"actual furnished building places: "+id):stage.free();continue
			var focus:Vector3=plan.anchors[0].position
			structures.blocks.set_focus(focus);structures.blocks.set_collision_radius(64);structures.blocks.flush_bakes();structures.set_model_focus(focus)
			var bounds:AABB=asset.placement_bounds(origin,turn);var deadline:=Time.get_ticks_msec()+10000
			while not structures.is_collision_region_ready(bounds) and Time.get_ticks_msec()<deadline:await process_frame
			var host=preload("res://addons/characters/runtime/zombie_world.gd").new();host.population_enabled=false;host.enabled=true;host.residency_limit=16
			host.target=Node3D.new();stage.add_child(host.target);host.target.position=Vector3(origin)+Vector3(80,0,80)
			host.readiness=structures.is_collision_region_ready;stage.add_child(host);await frames()
			for anchor:Dictionary in plan.anchors:
				var point:Vector3=anchor.position
				var roof:Dictionary=stage.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*1.9,point+Vector3.UP*16,7))
				check(not roof.is_empty(),"resident is indoors below a roof: %s %s"%[id,point])
				var actor:CharacterBody3D=host.spawn_at(point,true,true)
				if not check(actor!=null,"resident has actual support: %s %s"%[id,point]):continue
				actor.rotation.y=anchor.yaw;actor.set_physics_process(false)
				if check(host.put_to_sleep(actor,anchor.pose),"authored sleeping pose clears furnished room: "+id):
					actor.sleeper.wake()
					for step in 120:actor.sleeper.advance_wake(.05)
					check(actor.sleeper.phase=="ready" and not actor.sleeper.blocked,"entire standing wake clears furnishings: "+id)
			check(host.residents.size()==plan.anchors.size(),"complete small group is physically present: "+id)
			check(store.register_sleepers(plan.anchors).get("ok",false),"group fits existing persistent authored capacity: "+id)
			host.clear();stage.free();await frames()
	var ids:PackedInt64Array=store.authored_identities(PackedInt64Array([all_anchors[0].key]))
	var resident:Dictionary=store.resident(ids[0]);var vitals:PackedByteArray=resident.vitals;vitals.encode_float(0,0.)
	check(store.update_resident(ids[0],resident.position,resident.yaw,vitals),"clearing an authored resident records death")
	var snapshot:PackedByteArray=store.capture_snapshot();var replay:Dictionary=store.register_sleepers(all_anchors)
	check(replay.ok and replay.added==0 and store.capture_snapshot()==snapshot,"generation registration is deterministic and never refills dead residents")
	FileAccess.open(folder.path_join("population.bin"),FileAccess.WRITE).store_buffer(snapshot)
	FileAccess.open(folder.path_join("population.meta"),FileAccess.WRITE).store_var({"dead":ids[0],"anchors":all_anchors})
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"anchors":all_anchors.size()},"  "))
	finish()
func finish()->void:
	print("BUILDING_RESIDENTS checks=",checks," failures=",failures);quit(1 if failures else 0)
