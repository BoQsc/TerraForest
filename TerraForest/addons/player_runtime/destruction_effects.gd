# SPDX-License-Identifier: 0BSD
extends Node3D
const LIMIT:=96
var fragments:Array[Dictionary]=[]
var flashes:Array[Dictionary]=[]
var blocks:Node3D
var suspended:=false
var colors:=[Color("a78a75"),Color("7c603e"),Color("9c9f98"),Color("657580")]
func block(cell:Vector3i,word:int,origin:Vector3,force:float)->void:
	if fragments.size()>=LIMIT:
		fragments.pop_front().body.queue_free()
	var definition:Dictionary=blocks.decode_block(word)
	var mesh:Mesh=blocks.preview_mesh(definition.shape,definition.rotation)
	if mesh==null:return
	var body:=RigidBody3D.new();body.mass=[12.0,5.0,18.0,20.0][definition.material]
	body.collision_layer=1<<20;body.collision_mask=1|2|4;body.continuous_cd=true
	var view:=MeshInstance3D.new();view.mesh=mesh;view.position=-Vector3.ONE*.5
	var material:=StandardMaterial3D.new();material.albedo_color=colors[definition.material];material.roughness=.9;view.material_override=material;body.add_child(view)
	var collision:=CollisionShape3D.new();collision.shape=mesh.create_convex_shape(true,true);collision.position=-Vector3.ONE*.5;body.add_child(collision)
	add_child(body);body.global_position=Vector3(cell)+Vector3.ONE*.5
	var outward:Vector3=(body.global_position-origin).normalized()
	if outward.is_zero_approx():outward=Vector3.UP
	body.linear_velocity=(outward+Vector3.UP*.6).normalized()*force
	body.angular_velocity=Vector3(sin(cell.x*1.7),cos(cell.y*.9),sin(cell.z*1.1))*4
	fragments.append({"body":body,"remaining":8.0})
func explosion(point:Vector3)->void:
	var view:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.5;sphere.height=1;view.mesh=sphere
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(1,.4,.06,.8);material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;view.material_override=material
	add_child(view);view.global_position=point
	var light:=OmniLight3D.new();light.light_color=Color(1,.5,.15);light.omni_range=12;light.light_energy=5;view.add_child(light)
	flashes.append({"node":view,"age":0.0})
func step(delta:float,active:bool)->void:
	if suspended==active:
		suspended=not active
		for fragment in fragments:fragment.body.freeze=suspended
	if not active:return
	for index in range(fragments.size()-1,-1,-1):
		fragments[index].remaining-=delta
		if fragments[index].remaining<=0:fragments[index].body.queue_free();fragments.remove_at(index)
	for index in range(flashes.size()-1,-1,-1):
		var flash:Dictionary=flashes[index];flash.age+=delta
		if flash.age>=.5:flash.node.queue_free();flashes.remove_at(index);continue
		flash.node.scale=Vector3.ONE*(.2+flash.age*13)
		flash.node.material_override.albedo_color.a=.8*(1-flash.age/.5)
func clear()->void:
	for fragment in fragments:fragment.body.queue_free()
	for flash in flashes:flash.node.queue_free()
	fragments.clear();flashes.clear()
