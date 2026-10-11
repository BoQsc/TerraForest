# SPDX-License-Identifier: 0BSD
extends RefCounted
# Cached asset construction only; no per-frame procedural work.
static var cached:Mesh
static func mesh() -> Mesh:
 if cached!=null:return cached
 var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var metal:=StandardMaterial3D.new();metal.albedo_color=Color("667a80");metal.metallic=0.6;metal.roughness=0.45;st.set_material(metal)
 for i in 16:
  var a:=TAU*i/16;var b:=TAU*(i+1)/16
  var low_a:=Vector3(cos(a)*0.105,-0.12,sin(a)*0.105);var low_b:=Vector3(cos(b)*0.105,-0.12,sin(b)*0.105)
  var top_a:=Vector3(cos(a)*0.145,0.12,sin(a)*0.145);var top_b:=Vector3(cos(b)*0.145,0.12,sin(b)*0.145)
  var inner_a:=Vector3(cos(a)*0.13,0.12,sin(a)*0.13);var inner_b:=Vector3(cos(b)*0.13,0.12,sin(b)*0.13)
  for tri in [[low_a,top_a,top_b],[low_a,top_b,low_b],[top_a,inner_a,inner_b],[top_a,inner_b,top_b],[inner_a,Vector3(0,-0.10,0),inner_b],[low_b,Vector3(0,-0.12,0),low_a]]:
   for v:Vector3 in tri:st.add_vertex(v)
 # Narrow arched handle, joined into the same static mesh.
 for i in 12:
  var a:=PI*i/12;var b:=PI*(i+1)/12
  var p:=Vector3(cos(a)*0.145,0.12+sin(a)*0.16,0);var q:=Vector3(cos(b)*0.145,0.12+sin(b)*0.16,0)
  for tri in [[p-Vector3(0,0,0.012),q-Vector3(0,0,0.012),q+Vector3(0,0,0.012)],[p-Vector3(0,0,0.012),q+Vector3(0,0,0.012),p+Vector3(0,0,0.012)]]:
   for v:Vector3 in tri:st.add_vertex(v)
 st.generate_normals();cached=st.commit();return cached
