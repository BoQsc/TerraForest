# SPDX-License-Identifier: 0BSD
extends Node3D
## Constant-size editor feedback; never expands the selected cells into nodes.
var bounds:=MeshInstance3D.new()
var marker_a:=MeshInstance3D.new()
var marker_b:=MeshInstance3D.new()
var bounds_material:=StandardMaterial3D.new()

func _ready() -> void:
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1),Vector3(0,0,1),Vector3(0,1,0),Vector3(1,1,0),Vector3(1,1,1),Vector3(0,1,1)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,1,2,2,3,3,0,4,5,5,6,6,7,7,4,0,4,1,5,2,6,3,7])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
	for item: MeshInstance3D in [bounds,marker_a,marker_b]:
		item.mesh=mesh;item.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(item);item.hide()
	bounds_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	bounds.material_override=bounds_material
	for pair: Array in [[marker_a,Color("50c7ff")],[marker_b,Color("ffbb55")]]:
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=pair[1]
		pair[0].material_override=material

func synchronize(library: RefCounted) -> void:
	marker_a.visible=library.has_a;marker_b.visible=library.has_b
	marker_a.position=Vector3(library.corner_a)-Vector3.ONE*0.01;marker_a.scale=Vector3.ONE*1.02
	marker_b.position=Vector3(library.corner_b)-Vector3.ONE*0.01;marker_b.scale=Vector3.ONE*1.02
	bounds.visible=library.has_a and library.has_b
	if bounds.visible:
		bounds.position=Vector3(library.corner_a.min(library.corner_b))
		bounds.scale=Vector3((library.corner_b-library.corner_a).abs()+Vector3i.ONE)
		bounds_material.albedo_color=Color("ffd879") if library.selection_within_limit() else Color("ff705f")
