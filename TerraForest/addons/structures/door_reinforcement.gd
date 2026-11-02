# SPDX-License-Identifier: 0BSD
extends Node3D

const Meshes=preload("res://addons/structures/door_reinforcement_mesh.gd")
var collection:Node3D
var locks:RefCounted
var fit:=Transform3D.IDENTITY
var batches:Dictionary={}
var shown:Dictionary={}
var dirty:=false
var pending:=PackedInt64Array()
var cursor:=0
var focus:=Vector3.ZERO

func configure(owner:Node3D,ledger:RefCounted,bounds:AABB)->void:
	collection=owner;locks=ledger
	fit=Transform3D(Basis.from_scale(Vector3(bounds.size.x,bounds.size.y/2.0,1)),Vector3(bounds.position.x,bounds.position.y,bounds.get_center().z))
	owner.changed.connect(invalidate);locks.changed.connect(invalidate)
	set_process(false);invalidate()

func invalidate()->void:dirty=true;set_process(true)

func set_focus(point:Vector3)->void:
	focus=point
	for batch:Node3D in batches.values():batch.set_render_focus(point)

func _batch(stage:int)->Node3D:
	if batches.has(stage):return batches[stage]
	var batch:Node3D=ClassDB.instantiate("NativeStaticBatch")
	if not batch.configure_asset("presentation/door_reinforcement/%d"%stage,Meshes.build(stage)):
		batch.free();return null
	batch.configure_render_streaming(true,384,64,2*1024*1024,2,128*1024)
	batch.set_render_focus(focus);batch.set_shadow_distance(64)
	add_child(batch);batches[stage]=batch;return batch

func _process(_delta:float)->void:
	if cursor>=pending.size():
		if not dirty:set_process(false);return
		dirty=false;cursor=0;pending=locks.store.get_ids()
		for identity:int in shown:
			if not locks.store.is_locked(identity):pending.append(identity)
	var limit:=mini(pending.size(),cursor+16)
	while cursor<limit:
		var identity:int=pending[cursor];cursor+=1
		var values:PackedFloat32Array=collection.get_instance(identity)
		var state:Dictionary=locks.store.lock_state(identity)
		var stage:int=ceili(float(state.remaining)*3.0/state.maximum) if state.locked and values.size()==12 else 0
		var old:int=shown.get(identity,0)
		if old!=0 and old!=stage:
			batches[old].remove_instances(PackedInt64Array([identity]));shown.erase(identity)
		if stage==0:continue
		var pose:=Transform3D(Basis(Vector3(values[0],values[4],values[8]),Vector3(values[1],values[5],values[9]),Vector3(values[2],values[6],values[10])),Vector3(values[3],values[7],values[11]))*fit
		var transforms:=PackedFloat32Array()
		for row in 3:
			for column in 3:transforms.append(pose.basis[column][row])
			transforms.append(pose.origin[row])
		var batch:=_batch(stage)
		if batch!=null and batch.upsert_instances(PackedInt64Array([identity]),transforms):shown[identity]=stage
	if cursor>=pending.size() and not dirty:set_process(false)
