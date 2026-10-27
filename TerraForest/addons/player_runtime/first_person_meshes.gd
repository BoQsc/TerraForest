extends RefCounted

const ARM_LAYER=1<<18
const BODY_LAYER=1<<19
const BODY=preload("res://addons/characters/runtime/assets/first_person/body_body.res")
const ARMS=preload("res://addons/characters/runtime/assets/first_person/body_arms.res")
const UNARMED_BODY=preload("res://addons/characters/runtime/assets/first_person/unarmed_body.res")
const UNARMED_ARMS=preload("res://addons/characters/runtime/assets/first_person/unarmed_arms.res")
const SHIRT=preload("res://addons/characters/runtime/assets/first_person/shirt_body.res")
const SLEEVES=preload("res://addons/characters/runtime/assets/first_person/shirt_arms.res")
var pairs:Array[Dictionary]=[]
var equipment:Array[GeometryInstance3D]=[]
var original_layers:PackedInt32Array=[]
var active:=false
var overlay:=false
var tools:Node3D
var depth=preload("res://addons/player_runtime/first_person_depth.gd").new()

func prepare(source:Node3D)->void:
	tools=source
	var human:Node3D=tools.human
	add_pair(human.body_mesh,{human.original_body_mesh:[BODY,ARMS],human.unarmed_body_mesh:[UNARMED_BODY,UNARMED_ARMS]})
	var shirt:MeshInstance3D=human.model.find_child("Wardrobe_WorkShirt",true,false)
	add_pair(shirt,{shirt.mesh:[SHIRT,SLEEVES]})
	for node:Node in tools.find_children("*","GeometryInstance3D",true,false):register_geometry(node.get_instance_id())
	tools.get_tree().node_added.connect(node_added)

func node_added(node:Node)->void:
	if node is GeometryInstance3D and tools.is_ancestor_of(node):register_geometry.call_deferred(node.get_instance_id())

func register_geometry(identity:int)->void:
	var node:=instance_from_id(identity) as GeometryInstance3D
	if not is_instance_valid(node) or node in equipment:return
	var ancestor:Node=node
	while ancestor!=null and ancestor!=tools:
		if ancestor.get_meta("first_person_equipment",false) or String(ancestor.name).begins_with("Equipment_") or ancestor in tools.tools.values():
			equipment.append(node);original_layers.append(node.layers);depth.register(node)
			node.tree_exiting.connect(remove_geometry.bind(node),CONNECT_ONE_SHOT)
			if active and overlay:node.layers=ARM_LAYER
			return
		ancestor=ancestor.get_parent()

func remove_geometry(node:GeometryInstance3D)->void:
	var index:=equipment.find(node)
	if index<0:return
	node.layers=original_layers[index];depth.release(node)
	equipment.remove_at(index);original_layers.remove_at(index)

func set_overlay(value:bool)->void:
	if overlay==value:return
	overlay=value
	for index in equipment.size():equipment[index].layers=ARM_LAYER if active and overlay else original_layers[index]
	for pair in pairs:pair.arms.layers=ARM_LAYER if overlay else BODY_LAYER

func add_pair(source:MeshInstance3D,variants:Dictionary)->void:
	for original:Mesh in variants:
		for mesh:Mesh in variants[original]:
			var surfaces:PackedInt32Array=mesh.get_meta("source_surfaces")
			for surface in surfaces.size():mesh.surface_set_material(surface,original.surface_get_material(surfaces[surface]))
	var arms:=MeshInstance3D.new();arms.name=String(source.name)+"FirstPersonArms"
	arms.transform=source.transform;arms.skin=source.skin;arms.skeleton=source.skeleton
	arms.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;arms.layers=BODY_LAYER;arms.hide()
	source.get_parent().add_child(arms)
	pairs.append({"source":source,"arms":arms,"variants":variants,"original":source.mesh,"channels":PackedInt32Array()})

func change_mesh(node:MeshInstance3D,mesh:Mesh)->void:
	if node.mesh==mesh:return
	var values:PackedFloat32Array=[]
	for shape in node.get_blend_shape_count():values.append(node.get_blend_shape_value(shape))
	node.mesh=mesh
	for shape in mini(values.size(),node.get_blend_shape_count()):node.set_blend_shape_value(shape,values[shape])

func set_active(value:bool)->void:
	if active==value:return
	active=value
	for index in equipment.size():equipment[index].layers=ARM_LAYER if active and overlay else original_layers[index]
	if active:sync();return
	for pair in pairs:
		pair.arms.hide()
		if not pair.variants.has(pair.source.mesh):change_mesh(pair.source,pair.original)

func sync()->void:
	if not active:return
	for pair in pairs:
		var source:MeshInstance3D=pair.source
		var arms:MeshInstance3D=pair.arms
		if pair.variants.has(source.mesh):
			pair.original=source.mesh
			var variant:Array=pair.variants[source.mesh]
			change_mesh(source,variant[0])
			depth.release(arms);arms.mesh=variant[1];pair.channels=arms.mesh.get_meta("source_blend_shapes")
			var surfaces:PackedInt32Array=arms.mesh.get_meta("source_surfaces")
			for surface in surfaces.size():arms.set_surface_override_material(surface,source.get_surface_override_material(surfaces[surface]))
			depth.register(arms)
		arms.visible=source.visible;arms.transform=source.transform
		var channels:PackedInt32Array=pair.channels
		for shape in channels.size():
			var weight:=source.get_blend_shape_value(channels[shape])
			if arms.get_blend_shape_value(shape)!=weight:arms.set_blend_shape_value(shape,weight)

func dispose()->void:
	if tools.get_tree().node_added.is_connected(node_added):tools.get_tree().node_added.disconnect(node_added)
	depth.dispose()
	set_active(false)
	for pair in pairs:
		if is_instance_valid(pair.arms):pair.arms.queue_free()
	pairs.clear();equipment.clear()
