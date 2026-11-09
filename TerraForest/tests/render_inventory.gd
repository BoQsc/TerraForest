# SPDX-License-Identifier: 0BSD
extends RefCounted
## Diagnostic only: run after timing capture. Reading instance buffers may sync
## with rendering. AABB candidates are not actual submitted/occluded draw counts.
static func overlaps_sphere(bounds:AABB,centre:Vector3,radius:float)->bool:
	return centre.clamp(bounds.position,bounds.end).distance_squared_to(centre)<=radius*radius

static func capture(root:Node)->Dictionary:
	var pending:Array[Node]=[root]
	var geometry:Array[GeometryInstance3D]=[]
	var lights:Array[OmniLight3D]=[]
	while not pending.is_empty():
		var node:Node=pending.pop_back()
		pending.append_array(node.get_children())
		if node is GeometryInstance3D and node.is_visible_in_tree():geometry.append(node)
		if node is OmniLight3D and node.is_visible_in_tree() and node.shadow_enabled:lights.append(node)
	var rows:Array[Dictionary]=[]
	var lamp_rows:Array[Dictionary]=[]
	for lamp:OmniLight3D in lights:
		lamp_rows.append({"path":str(root.get_path_to(lamp)),"position":lamp.global_position,"range":lamp.omni_range,"caster_mask":lamp.shadow_caster_mask,"mode":lamp.omni_shadow_mode})
	for node:GeometryInstance3D in geometry:
		var mesh:Mesh
		var multi:MultiMesh
		if node is MeshInstance3D:mesh=node.mesh
		elif node is MultiMeshInstance3D:
			multi=node.multimesh
			if multi!=null:mesh=multi.mesh
		if mesh==null:continue
		var count:=1 if multi==null else (multi.instance_count if multi.visible_instance_count<0 else mini(multi.instance_count,multi.visible_instance_count))
		var triangles:=0
		if mesh is ArrayMesh:
			for surface:int in mesh.get_surface_count():
				if mesh.surface_get_primitive_type(surface)==Mesh.PRIMITIVE_TRIANGLES:
					var indices:int=mesh.surface_get_array_index_len(surface)
					triangles+=(indices if indices>0 else mesh.surface_get_array_len(surface))/3
		var bounds:AABB=node.global_transform*node.get_aabb()
		var candidates:Array[Dictionary]=[]
		if node.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			for index:int in lights.size():
				var lamp:OmniLight3D=lights[index]
				if not (node.layers&lamp.shadow_caster_mask) or not overlaps_sphere(bounds,lamp.global_position,lamp.omni_range):continue
				var exact_count:=count
				if multi!=null:
					exact_count=0
					for slot:int in count:
						var instance_bounds:AABB=(node.global_transform*multi.get_instance_transform(slot))*mesh.get_aabb()
						if overlaps_sphere(instance_bounds,lamp.global_position,lamp.omni_range):exact_count+=1
				candidates.append({"light":index,"batch_instances":count,"overlapping_instance_bounds":exact_count})
		rows.append({"path":str(root.get_path_to(node)),"mesh":mesh.resource_path,"surfaces":mesh.get_surface_count(),"instances":count,"triangles_per_instance":triangles,"world_bounds":bounds,"shadow":node.cast_shadow,"point_light_candidates":candidates})
	return {"scope":"Post-capture scene inventory. Conservative light-sphere/AABB candidates, not actual renderer draw submissions or occlusion. Triangle counts omit non-ArrayMesh and non-triangle primitives.","lights":lamp_rows,"geometry":rows}
