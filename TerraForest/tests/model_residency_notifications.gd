# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func drain(batch:Node3D,retiring:bool)->Dictionary:
	var state:Dictionary={}
	for tick in 10000:
		state=batch.advance_region_retirement(64,4096,500) if retiring else batch.advance_region_admission(64,4096,500)
		if not state.get("active",false):return state
	return state
func run()->void:
	var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world)
	check(world.prepare(),"structure world prepares")
	var batch:Node3D=world.register_model("test/residency",BoxMesh.new())
	var cover=preload("res://addons/world_ecosystem/ground_cover.gd").new()
	cover._wanted[Vector2i(30,30)]=true
	world.vegetation_changed.connect(cover._exclusion_changed)
	var signals:Dictionary={"world":0,"collection":0}
	world.changed.connect(func():signals.world+=1)
	batch.changed.connect(func():signals.collection+=1)
	var pose:=PackedFloat32Array([1,0,0,970,0,1,0,65,0,0,1,970])
	check(batch.upsert_instances(PackedInt64Array([1]),pose) and signals.world>0 and cover._dirty.size()==1,"authored model insertion invalidates world vegetation")
	var packet:PackedByteArray=batch.capture_region(Vector3i(30,2,30))
	var snapshot:PackedByteArray=batch.capture_snapshot()
	for mode in ["raw_retire","raw_admit","incremental_retire","incremental_admit"]:
		signals.world=0;signals.collection=0;cover._dirty.clear();world._dirty=false;world._cached_storage=PackedByteArray([42])
		var revision:int=cover._exclusion_revision
		var accepted:bool
		if mode=="raw_retire":accepted=batch.unload_region(packet)
		elif mode=="raw_admit":accepted=batch.restore_region(packet)
		else:
			var retiring:bool=mode=="incremental_retire"
			accepted=batch.begin_region_retirement(packet) if retiring else batch.begin_region_admission(packet)
			if accepted:accepted=drain(batch,retiring).get("result","")=="complete"
		check(accepted and signals.collection==1,"storage notifications remain observable: "+mode)
		check(world._dirty and world._cached_storage.is_empty(),"paging invalidates derived snapshot cache: "+mode)
		check(signals.world==0 and cover._dirty.is_empty() and cover._exclusion_revision==revision,"unchanged paging neither dirties save nor regenerates cover: "+mode)
	var history:RefCounted=ClassDB.instantiate("NativeStaticHistory");history.configure([batch],65536,32)
	for retiring in [true,false]:
		signals.world=0;signals.collection=0;cover._dirty.clear()
		var ticket:int=history.begin_region_retirement(batch,packet) if retiring else history.begin_region_admission(batch,packet)
		var state:Dictionary={}
		for tick in 10000:
			state=history.advance_region_retirement(batch,ticket,64,4096,500) if retiring else history.advance_region_admission(batch,ticket,64,4096,500)
			if not state.get("active",false):break
		check(ticket>0 and state.get("result","")=="complete" and signals.collection==1,"journal-owned transfer preserves collection notification")
		check(signals.world==0 and cover._dirty.is_empty(),"journal-owned transfer does not become an authored world edit")
	for retiring in [true,false]:
		signals.world=0;signals.collection=0;cover._dirty.clear()
		var accepted:bool=history.unload_region(batch,packet) if retiring else history.restore_region(batch,packet)
		check(accepted and signals.collection==1 and signals.world==0 and cover._dirty.is_empty(),"synchronous journal transfer preserves content without notifying authoring")
	var moved:=pose.duplicate();moved[7]+=1
	for action in ["update","undo","redo","erase","restore"]:
		signals.world=0;cover._dirty.clear()
		var accepted:bool
		match action:
			"update":accepted=history.update(batch,1,moved,AABB())
			"undo":accepted=history.undo()
			"redo":accepted=history.redo()
			"erase":accepted=history.erase(batch,1)
			"restore":accepted=batch.restore_snapshot(snapshot)
		check(accepted and signals.world>0 and cover._dirty.size()==1,"real authoring still invalidates vegetation: "+action)
	check(batch.capture_snapshot()==snapshot,"storage cycles and restored edits retain exact original canonical bytes")
	var blocks:Node3D=world.blocks
	blocks.configure_history(65536,32)
	signals.world=0;cover._dirty.clear()
	check(blocks.set_cells(PackedInt32Array([970,65,970,1])) and signals.world==1 and cover._dirty.size()==1,"authored blocks still invalidate nearby cover")
	var block_packet:PackedByteArray=blocks.capture_region(Vector3i(15,1,15))
	for retiring in [true,false]:
		signals.world=0;cover._dirty.clear();world._dirty=false;world._cached_storage=PackedByteArray([42])
		var revision:int=cover._exclusion_revision
		var accepted:bool=blocks.unload_region(block_packet) if retiring else blocks.restore_region(block_packet,PackedByteArray())
		check(accepted and signals.world==0 and cover._dirty.is_empty() and cover._exclusion_revision==revision,"block paging retains cover and does not become an authored edit")
		check(world._dirty and world._cached_storage.is_empty(),"block residency still invalidates cached snapshot")
	for replay in ["undo","redo","restore"]:
		signals.world=0;cover._dirty.clear()
		var accepted:bool
		if replay=="restore":accepted=blocks.restore_snapshot(world._empty_blocks)
		else:
			if replay=="undo":blocks.set_cells(PackedInt32Array([971,65,970,1]));signals.world=0;cover._dirty.clear()
			accepted=blocks.undo() if replay=="undo" else blocks.redo()
		check(accepted and signals.world==1 and cover._dirty.size()==1,"block content notification survives "+replay)
	var prefab:Resource=ClassDB.instantiate("NativeBlockPrefab")
	var placement:RefCounted=ClassDB.instantiate("NativePrefabPlacement")
	prefab.configure(PackedInt32Array([0,0,0,1,1,0,0,1]))
	signals.world=0;cover._dirty.clear()
	var content_revision:int=blocks.survey_content_revision_id()
	var result:Dictionary=placement.place(blocks,prefab,Vector3i(970,65,970),0,{},[])
	check(result.get("ok",false) and blocks.survey_content_revision_id()>content_revision,"staged block-only prefab advances content revision")
	check(signals.world==1 and cover._dirty.size()==1,"staged block-only prefab invalidates vegetation without attached models")
	for journalled in [false,true]:
		var disposable:Node3D=ClassDB.instantiate("NativeStaticBatch")
		disposable.configure_asset("test/disposable",BoxMesh.new())
		var journal:RefCounted=ClassDB.instantiate("NativeStaticHistory");journal.configure([disposable],65536,32)
		var other:=Node.new()
		var notices:Dictionary={"exclusion":0,"reentered":true}
		disposable.exclusion_changed.connect(func():notices.exclusion+=1;notices.reentered=journal.undo())
		disposable.changed.connect(func():other.free(),CONNECT_ONE_SHOT)
		var accepted:bool=journal.insert(disposable,pose)>0 if journalled else disposable.upsert_instances(PackedInt64Array([1]),pose)
		check(accepted and notices.exclusion==1 and not notices.reentered and not is_instance_valid(other),"content observers preserve reentrancy guard after changed callbacks")
		disposable.free()
	cover.free();world.free()
	print("MODEL_RESIDENCY_NOTIFICATIONS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
