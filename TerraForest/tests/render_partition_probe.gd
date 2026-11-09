# SPDX-License-Identifier: 0BSD
extends RefCounted
## Stationary A/B diagnostic. Copies exact instance records/materials into
## smaller draw groups; the gameplay owner and authored state are untouched.
var originals:Array[MultiMeshInstance3D]=[]
var buffers:Array[PackedFloat32Array]=[]
var replacements:Array[MultiMeshInstance3D]=[]
var replacement_buffers:Array[PackedFloat32Array]=[]
var instance_count:=0
func prepare(game:Node,span:float)->void:
	for batch:Node3D in game.ground_cover.batches:
		for node:Node in batch.get_children():
			if not node is MultiMeshInstance3D or not node.is_visible_in_tree():continue
			var multi:MultiMesh=node.multimesh
			if multi==null or multi.instance_count==0 or multi.visible_instance_count!=-1:continue
			var bounds:AABB=node.global_transform*node.get_aabb()
			if game.player.global_position.clamp(bounds.position,bounds.end).distance_to(game.player.global_position)>32:continue
			assert(node.material_override==null and node.material_overlay==null)
			var source:PackedFloat32Array=multi.buffer
			var stride:=12+(4 if multi.use_colors else 0)+(4 if multi.use_custom_data else 0)
			assert(source.size()==stride*multi.instance_count)
			var groups:Dictionary={}
			for slot:int in multi.instance_count:
				var at:=slot*stride
				var origin:=Vector3(source[at+3],source[at+7],source[at+11])
				var key:=Vector3i((origin/span).floor())
				if not groups.has(key):groups[key]=PackedFloat32Array()
				var group:PackedFloat32Array=groups[key];group.append_array(source.slice(at,at+stride));groups[key]=group
			if groups.size()<2:continue
			originals.append(node);buffers.append(source);instance_count+=multi.instance_count
			for key:Vector3i in groups:
				var replacement:=MultiMeshInstance3D.new();replacement.visible=false;game.add_child(replacement)
				replacement.global_transform=node.global_transform;replacement.layers=node.layers;replacement.cast_shadow=node.cast_shadow;replacement.extra_cull_margin=node.extra_cull_margin
				var split:=MultiMesh.new();split.transform_format=multi.transform_format;split.use_colors=multi.use_colors;split.use_custom_data=multi.use_custom_data
				split.mesh=multi.mesh;split.instance_count=groups[key].size()/stride;split.buffer=groups[key];replacement.multimesh=split
				replacements.append(replacement);replacement_buffers.append(groups[key])
func unchanged()->bool:
	for index:int in originals.size():
		if not is_instance_valid(originals[index]) or originals[index].multimesh.buffer!=buffers[index]:return false
	for index:int in replacements.size():
		if replacements[index].multimesh.buffer!=replacement_buffers[index]:return false
	return true
func set_partitioned(enabled:bool)->void:
	for node:MultiMeshInstance3D in originals:node.visible=not enabled
	for node:MultiMeshInstance3D in replacements:node.visible=enabled
func release()->void:
	set_partitioned(false)
	for node:MultiMeshInstance3D in replacements:node.free()
	replacements.clear();replacement_buffers.clear();originals.clear();buffers.clear()
