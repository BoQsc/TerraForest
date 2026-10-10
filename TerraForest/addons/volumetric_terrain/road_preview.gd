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
func update_selection(a: Vector3,b: Vector3,half_width: float,depth: float,valid: bool,clearance: float=0.0,shoulder: float=0.0) -> void:
	outline.clear_surfaces();rebuilds+=1
	appearance.no_depth_test=false
	if not a.is_finite() or not b.is_finite(): return
	appearance.albedo_color=Color("50e6b5") if valid else Color("ff705e")
	var axis:=Vector3(b.x-a.x,0,b.z-a.z).normalized()
	if axis.length_squared()<0.5: axis=Vector3.RIGHT
	var side:=Vector3(-axis.z,0,axis.x)
	var ring:=PackedVector3Array()
	var outer:=PackedVector3Array()
	# Two semicircles match the native rounded footprint and constant end heights.
	for end in 2:
		var center: Vector3=b if end==0 else a
		for i in 13:
			var angle: float=-PI*0.5+PI*i/12.0+PI*end
			ring.append(center+(axis*cos(angle)+side*sin(angle))*half_width)
			outer.append(center+(axis*cos(angle)+side*sin(angle))*(half_width+shoulder)-Vector3.UP*depth)
	outline.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in ring.size():
		var next: int=(i+1)%ring.size()
		_line(ring[i],ring[next])
		if shoulder>0:
			_line(outer[i],outer[next])
			if i%6==0: _line(ring[i],outer[i])
		_line(ring[i]-Vector3.UP*depth,ring[next]-Vector3.UP*depth)
		if clearance>0:
			_line(ring[i]+Vector3.UP*clearance,ring[next]+Vector3.UP*clearance)
			if i%6==0: _line(ring[i],ring[i]+Vector3.UP*clearance)
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

func update_curve(points: PackedVector3Array,half_width: float) -> void:
	outline.clear_surfaces();rebuilds+=1
	# Authoring overlay must remain visible where the proposed cut is underground.
	appearance.no_depth_test=true
	if points.size()<2:return
	appearance.albedo_color=Color("50e6b5")
	var axis:=points[-1]-points[0];axis.y=0;axis=axis.normalized()
	var side:=Vector3(-axis.z,0,axis.x)*half_width
	outline.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in points.size()-1:
		_line(points[i],points[i+1]);_line(points[i]+side,points[i+1]+side);_line(points[i]-side,points[i+1]-side)
	_line(points[0]-side,points[0]+side);_line(points[-1]-side,points[-1]+side)
	outline.surface_end()
