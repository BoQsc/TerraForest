# SPDX-License-Identifier: 0BSD
extends Node3D
signal block_profiled(profile:Dictionary)
const LIMIT:=96
var fragments:Array[Dictionary]=[]
var flashes:Array[Dictionary]=[]
var blocks:Node3D
var suspended:=false
var colors:=[Color("a78a75"),Color("7c603e"),Color("9c9f98"),Color("657580")]
const BAKED_GEOMETRY=preload("res://addons/player_runtime/assets/debris_geometry.res")
const GEOMETRY_LIMIT:=128
var geometry:Dictionary={}
var materials:Array[Material]=[]
var convex_builds:=0
var geometry_loads:=0
func _geometry(definition:Dictionary)->Dictionary:
	var key:=Vector2i(definition.shape,definition.rotation)
	if geometry.has(key):return geometry[key]
	var mesh:Mesh=blocks.preview_mesh(definition.shape,definition.rotation)
	if mesh==null:return {}
	var shape:ConvexPolygonShape3D=BAKED_GEOMETRY.get_meta("shapes",{}).get(key)
	if shape==null:
		# Authoring fallback only. The export gate bakes every supported pose;
		# gameplay never has to run the expensive decomposition algorithm.
		shape=mesh.create_convex_shape(true,true);convex_builds+=1
	if shape==null:return {}
	if geometry.size()>=GEOMETRY_LIMIT:geometry.erase(geometry.keys()[0])
	geometry[key]={"mesh":mesh,"shape":shape};geometry_loads+=1
	return geometry[key]
func _material(index:int)->Material:
	if materials.is_empty():
		for color:Color in colors:
			var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.9;materials.append(material)
	return materials[index]
func block(cell:Vector3i,word:int,origin:Vector3,force:float)->void:
	var profiling:bool=block_profiled.has_connections()
	var started:int=Time.get_ticks_usec() if profiling else 0
	if fragments.size()>=LIMIT:
		fragments.pop_front().body.queue_free()
	var definition:Dictionary=blocks.decode_block(word)
	var prototype:=_geometry(definition)
	if prototype.is_empty():return
	var geometry_done:int=Time.get_ticks_usec() if profiling else 0
	var body:=RigidBody3D.new();body.mass=[12.0,5.0,18.0,20.0][definition.material]
	body.collision_layer=1<<20;body.collision_mask=1|2|4;body.continuous_cd=true
	var view:=MeshInstance3D.new();view.mesh=prototype.mesh;view.position=-Vector3.ONE*.5
	view.material_override=_material(definition.material);body.add_child(view)
	var collision:=CollisionShape3D.new();collision.shape=prototype.shape;collision.position=-Vector3.ONE*.5;body.add_child(collision)
	var nodes_done:int=Time.get_ticks_usec() if profiling else 0
	add_child(body);body.global_position=Vector3(cell)+Vector3.ONE*.5
	var attached:int=Time.get_ticks_usec() if profiling else 0
	var outward:Vector3=(body.global_position-origin).normalized()
	if outward.is_zero_approx():outward=Vector3.UP
	body.linear_velocity=(outward+Vector3.UP*.6).normalized()*force
	body.angular_velocity=Vector3(sin(cell.x*1.7),cos(cell.y*.9),sin(cell.z*1.1))*4
	fragments.append({"body":body,"remaining":8.0})
	if profiling:
		var finished:=Time.get_ticks_usec()
		block_profiled.emit({"geometry_us":geometry_done-started,"nodes_us":nodes_done-geometry_done,"attach_us":attached-nodes_done,"motion_us":finished-attached,"total_us":finished-started})
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
