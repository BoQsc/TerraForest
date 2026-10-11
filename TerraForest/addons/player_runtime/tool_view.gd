# SPDX-License-Identifier: 0BSD
extends Node3D
# A handful of opaque meshes, built once; no idle processing or physics bodies.
var tools: Dictionary={}
var motion: Tween
var current:=0
func part(parent: Node3D,size: Vector3,at: Vector3,color: Color,angle: float=0.0) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=0.8
	var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=material;node.position=at;node.rotation.z=angle
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(node)
func point(parent: Node3D,at: Vector3,angle: float) -> void:
	var mesh:=CylinderMesh.new();mesh.top_radius=0.002;mesh.bottom_radius=0.035;mesh.height=0.16;mesh.radial_segments=6;mesh.rings=1
	var material:=StandardMaterial3D.new();material.albedo_color=Color("777e83");material.roughness=0.8
	var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=material;node.position=at;node.rotation.z=angle
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(node)
func _ready() -> void:
	position=Vector3(0.34,-0.32,-0.65);rotation=Vector3(-0.2,0.15,-0.28)
	for id in [1,2,3,4]:
		var root:=Node3D.new();add_child(root);tools[id]=root;root.hide()
		part(root,Vector3(0.045,0.42,0.045),Vector3.ZERO,Color("62472f"))
		if id==1:
			part(root,Vector3(0.19,0.055,0.055),Vector3(0,0.2,0),Color("777e83"))
			point(root,Vector3(-0.16,0.18,0),1.85);point(root,Vector3(0.16,0.18,0),-1.85)
		elif id==2:part(root,Vector3(0.16,0.14,0.045),Vector3(0.06,0.17,0),Color("81888b"),-0.12)
		elif id==3:part(root,Vector3(0.18,0.09,0.085),Vector3(0,0.2,0),Color("626a71"))
		else:
			part(root,Vector3(0.12,0.045,0.06),Vector3(0,0.18,0),Color("939b9c"))
			for x in [-0.05,0.05]:part(root,Vector3(0.035,0.09,0.06),Vector3(x,0.23,0),Color("939b9c"))
func equip(id: int) -> void:
	current=id
	if motion!=null:motion.kill()
	rotation.x=-0.2
	for key in tools:tools[key].visible=key==id
func swing() -> void:
	if current==0 or (motion!=null and motion.is_running()):return
	motion=create_tween();motion.tween_property(self,"rotation:x",-0.85,0.1);motion.tween_property(self,"rotation:x",-0.2,0.18)
