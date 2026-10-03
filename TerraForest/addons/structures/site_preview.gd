# SPDX-License-Identifier: 0BSD
extends MeshInstance3D
# Bounded authoring overlay: one mesh, rebuilt only for a new surveyed plan.
var outline:=ImmediateMesh.new()
var appearance:=StandardMaterial3D.new()
var rebuilds:=0
var vertices:=0
func _init() -> void:
	mesh=outline;cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	appearance.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	appearance.vertex_color_use_as_albedo=true
	appearance.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	appearance.no_depth_test=true
	material_override=appearance
	hide()
func clear() -> void:
	outline.clear_surfaces();vertices=0;hide()
func show_plan(plan: Dictionary) -> void:
	clear()
	if not plan.get("ok",false) or plan.get("segments",[]).is_empty() or plan.segments.size()>256: return
	rebuilds+=1
	outline.surface_begin(Mesh.PRIMITIVE_LINES)
	for segment: Dictionary in plan.segments:
		var a: Vector3=segment.start;var b: Vector3=segment.finish
		var axis: Vector3=(b-a).normalized();var side:=Vector3(-axis.z,0,axis.x)
		var top:=PackedVector3Array();var bank:=PackedVector3Array()
		for end in 2:
			var center: Vector3=b if end==0 else a
			for i in 13:
				var angle: float=-PI*0.5+PI*i/12.0+PI*end
				var radial:=axis*cos(angle)+side*sin(angle)
				top.append(center+radial*segment.half_width)
				bank.append(center+radial*(segment.half_width+segment.shoulder)-Vector3.UP*segment.depth)
		var color:=Color(0.2,0.85,1.0,0.9) if segment.material==4 else Color(0.4,1.0,0.5,0.8)
		for i in top.size():
			var next: int=(i+1)%top.size()
			_line(top[i],top[next],color)
			if segment.shoulder>0: _line(bank[i],bank[next],Color(1.0,0.65,0.2,0.7))
			if i%6==0:
				_line(top[i],bank[i],Color(1.0,0.65,0.2,0.6))
				_line(top[i],top[i]+Vector3.UP*segment.clearance,Color(1,1,1,0.4))
		_line(a,b,color)
	outline.surface_end();show()
func _line(a: Vector3,b: Vector3,color: Color) -> void:
	outline.surface_set_color(color);outline.surface_add_vertex(a);outline.surface_add_vertex(b);vertices+=2
