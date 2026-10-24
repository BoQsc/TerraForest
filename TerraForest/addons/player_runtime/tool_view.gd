# SPDX-License-Identifier: 0BSD
extends Node3D
# R11 animated character, with existing construction and water tool previews.
signal attack_contact(identity:int)
signal attack_finished(identity:int,cancelled:bool)
var attack_allowed:Callable
var attack_identity:=0
var contact_identity:=0
var tools: Dictionary={}
var motion: Tween
var current:=0
func part(parent: Node3D,size: Vector3,at: Vector3,color: Color,angle: float=0.0) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=0.8
	var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=material;node.position=at;node.rotation.z=angle
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(node)
var human = preload("res://addons/characters/runtime/human_view.gd").new()
func _ready() -> void:
	add_child(human)
	human.swing_contact.connect(func(identity:int):
		if identity>0 and identity==attack_identity:contact_identity=identity;attack_contact.emit(identity))
	human.swing_finished.connect(func(identity:int,cancelled:bool):
		if identity>0 and identity==attack_identity:
			attack_identity=0;attack_finished.emit(identity,cancelled))
	for id in [0,1,2,3,4]:
		var root := Node3D.new();add_child(root);tools[id]=root;root.hide()
		root.position=Vector3(0.34,-0.32,-0.65);root.rotation=Vector3(-0.2,0.15,-0.28)
		if id<=2:continue # R11 owns hands, pickaxe and axe.
		part(root,Vector3(0.045,0.42,0.045),Vector3.ZERO,Color("62472f"))
		if id==3:part(root,Vector3(0.18,0.09,0.085),Vector3(0,0.2,0),Color("626a71"))
		else:
			part(root,Vector3(0.12,0.045,0.06),Vector3(0,0.18,0),Color("939b9c"))
			for x in [-0.05,0.05]:part(root,Vector3(0.035,0.09,0.06),Vector3(x,0.23,0),Color("939b9c"))
func equip(id: int) -> void:
	cancel_attack()
	if id>=401 and id<=411:
		id=401
		if not tools.has(401):
			var bucket:=MeshInstance3D.new();bucket.mesh=preload("res://addons/volumetric_water/bucket_model.gd").mesh();bucket.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;bucket.position=Vector3(0.34,-0.32,-0.65);bucket.rotation=Vector3(-0.2,0.15,-0.28);add_child(bucket);tools[401]=bucket

	current=id
	if motion!=null:motion.kill()
	human.equip(id)
	for key in tools:
		tools[key].visible=key==id
		tools[key].rotation.x=-0.2
func attack_profile()->Dictionary:
	if current<=2:return human.swing_profile()
	if current in [3,4]:return {"clip":"tool_swing","contact":0.1,"duration":0.28}
	return {}
func begin_attack(identity:int)->bool:
	if identity<=0 or attack_identity!=0 or not is_visible_in_tree():return false
	attack_identity=identity
	contact_identity=0
	if not _swing(identity):attack_identity=0;return false
	return true
func cancel_attack()->void:
	if attack_identity==0:return
	var identity:=attack_identity;attack_identity=0
	contact_identity=0
	human.cancel_swing()
	if motion!=null:motion.kill()
	if tools.has(current):tools[current].rotation.x=-0.2
	attack_finished.emit(identity,true)
func swing() -> bool:return _swing(0)
func contact_ready(identity:int)->bool:
	if identity<=0 or identity!=attack_identity or identity!=contact_identity:return false
	return current>2 or (human.swing_identity==identity and human.contact_sent and human.animation_player.current_animation_position+0.00001>=human.contact_seconds)
func _swing(identity:int) -> bool:
	if current<=2:
		return human.swing(identity)
	if motion!=null and motion.is_running():return false
	if not tools.has(current):return false
	var preview:Node3D=tools[current]
	motion=create_tween();motion.tween_property(preview,"rotation:x",-0.85,0.1)
	if identity>0:motion.tween_callback(func():
		if identity==attack_identity:contact_identity=identity;attack_contact.emit(identity))
	motion.tween_property(preview,"rotation:x",-0.2,0.18)
	if identity>0:motion.tween_callback(func():
		if identity==attack_identity:attack_identity=0;attack_finished.emit(identity,false))
	return true

func place() -> bool:
	cancel_attack()
	if not human.place():return false
	if motion!=null:motion.kill()
	for preview in tools.values():preview.hide()
	return true

func _process(_delta:float)->void:
	if attack_identity>0 and (not is_visible_in_tree() or (attack_allowed.is_valid() and not attack_allowed.call())):cancel_attack()
	if tools.has(current):tools[current].visible=not human.placement_active
