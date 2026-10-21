# SPDX-License-Identifier: 0BSD
extends Node3D
# Presentation only. All local quantities, picking and editing stay native.
var coverage:ImageTexture
var proxy_material:ShaderMaterial
var last_coverage:=PackedByteArray()
func setup(material:ShaderMaterial)->void:
 var bytes:=PackedByteArray();bytes.resize(500*500);bytes.fill(0)
 coverage=ImageTexture.create_from_image(Image.create_from_data(500,500,false,Image.FORMAT_R8,bytes))
 material.set_shader_parameter("surrounding_ocean",true)
 material.set_shader_parameter("ocean_coverage",coverage)
 proxy_material=material.duplicate();proxy_material.set_shader_parameter("ocean_proxy",true)
 var horizon:ShaderMaterial=material.duplicate();horizon.set_shader_parameter("ocean_horizon",true)
 # One ring inside the existing terrain domain, one outside. Eight quads total.
 ring(Vector2.ZERO,Vector2(2000,2000),Vector2(140,140),Vector2(1860,1860),proxy_material)
 ring(Vector2(-8000,-8000),Vector2(10000,10000),Vector2.ZERO,Vector2(2000,2000),horizon)
func publish(bytes:PackedByteArray)->void:
 if bytes.size()!=500*500 or bytes==last_coverage:return
 last_coverage=bytes
 coverage.update(Image.create_from_data(500,500,false,Image.FORMAT_R8,bytes))
func ring(low:Vector2,high:Vector2,hole_low:Vector2,hole_high:Vector2,material:ShaderMaterial)->void:
 for rect:Rect2 in [Rect2(low,Vector2(hole_low.x-low.x,high.y-low.y)),Rect2(Vector2(hole_high.x,low.y),Vector2(high.x-hole_high.x,high.y-low.y)),Rect2(Vector2(hole_low.x,low.y),Vector2(hole_high.x-hole_low.x,hole_low.y-low.y)),Rect2(Vector2(hole_low.x,hole_high.y),Vector2(hole_high.x-hole_low.x,high.y-hole_high.y))]:
  var mesh:=PlaneMesh.new();mesh.size=rect.size
  var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=material
  node.position=Vector3(rect.get_center().x,40,rect.get_center().y)
  node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)
