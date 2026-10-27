extends RefCounted

const SCALE=.01
var active:=false
var entries:Dictionary={}
var materials:Dictionary={}

func protected_material(source:Material)->Material:
	if not source is BaseMaterial3D:return source
	if not materials.has(source):
		var copy:BaseMaterial3D=source.duplicate()
		copy.use_z_clip_scale=true;copy.z_clip_scale=SCALE
		materials[source]=copy
	return materials[source]

func register(node:GeometryInstance3D)->void:
	if entries.has(node):return
	var surfaces:Array=[]
	if node is MeshInstance3D and node.mesh!=null:
		for surface in node.mesh.get_surface_count():surfaces.append(node.get_surface_override_material(surface))
	entries[node]={"override":node.material_override,"surfaces":surfaces,"sorting":node.sorting_offset}
	apply(node)

func apply(node:GeometryInstance3D)->void:
	if not is_instance_valid(node):return
	var original:Dictionary=entries[node]
	node.sorting_offset=original.sorting+(64.0 if active else 0.0)
	node.material_override=protected_material(original.override) if active else original.override
	if node is MeshInstance3D and node.mesh!=null:
		for surface in mini(original.surfaces.size(),node.mesh.get_surface_count()):
			var source:Material=original.surfaces[surface]
			if active and original.override==null:
				if source==null:source=node.mesh.surface_get_material(surface)
				node.set_surface_override_material(surface,protected_material(source))
			else:node.set_surface_override_material(surface,source)
	if original.override is ShaderMaterial and original.override.shader.code.contains("first_person_depth_scale"):
		node.set_instance_shader_parameter("first_person_depth_scale",SCALE if active else 1.0)

func release(node:GeometryInstance3D)->void:
	if not entries.has(node):return
	var previous:=active;active=false;apply(node);active=previous
	entries.erase(node)

func set_active(value:bool)->void:
	if active==value:return
	active=value
	for node:Variant in entries:
		if is_instance_valid(node):apply(node)

func dispose()->void:
	set_active(false);entries.clear();materials.clear()
