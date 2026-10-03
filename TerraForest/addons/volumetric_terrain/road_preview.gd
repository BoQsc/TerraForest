# SPDX-License-Identifier: 0BSD
# Small editor-only outline, rebuilt on selection changes, never per terrain cell.
extends MeshInstance3D
var rebuilds:=0
var outline:=ImmediateMesh.new()
var appearance:=StandardMaterial3D.new()
func _init() -> void:
	mesh=outline
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	appearance.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material_override=appearance
func update_selection(a: Vector3,b: Vector3,half_width: float,depth: float,valid: bool) -> void:
	outline.clear_surfaces();rebuilds+=1
	if not a.is_finite() or not b.is_finite(): return
	appearance.albedo_color=Color("50e6b5") if valid else Color("ff705e")
	var axis:=Vector3(b.x-a.x,0,b.z-a.z).normalized()
	if axis.length_squared()<0.5: axis=Vector3.RIGHT
	var side:=Vector3(-axis.z,0,axis.x)
	var ring:=PackedVector3Array()
	# Two semicircles match the native rounded footprint and constant end heights.
	for end in 2:
		var center: Vector3=b if end==0 else a
		for i in 13:
			var angle: float=-PI*0.5+PI*i/12.0+PI*end
			ring.append(center+(axis*cos(angle)+side*sin(angle))*half_width)
	outline.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in ring.size():
		var next: int=(i+1)%ring.size()
		_line(ring[i],ring[next])
		_line(ring[i]-Vector3.UP*depth,ring[next]-Vector3.UP*depth)
		if i%6==0: _line(ring[i],ring[i]-Vector3.UP*depth)
	_line(a,b)
	for center: Vector3 in [a,b]:
		_line(center-Vector3.UP*0.5,center+Vector3.UP*0.5)
		_line(center-side*0.5,center+side*0.5)
	outline.surface_end()
func _line(a: Vector3,b: Vector3) -> void:
	outline.surface_add_vertex(a);outline.surface_add_vertex(b)
func clear() -> void:
	outline.clear_surfaces()
