# SPDX-License-Identifier: 0BSD
extends Node3D
## One held torch: a layered flame, 16 embers, eight smoke wisps, one light.
## Fixed budgets, presentation only. No terrain ignition or inventory mutation.
const FLAME=preload("res://addons/characters/runtime/torch_flame.gdshader")
const MOTES=preload("res://addons/characters/runtime/torch_motes.gdshader")
var lamp:OmniLight3D
var materials:Array[ShaderMaterial]=[]
var clock:=0.0
var burning:=false
func _ready()->void:
	var flame:=MeshInstance3D.new();flame.name="Flame"
	var quad:=QuadMesh.new();quad.size=Vector2(.135,.27)
	flame.mesh=quad;flame.position=Vector3(0,.36+quad.size.y*.44,0)
	var material:=ShaderMaterial.new();material.shader=FLAME
	flame.material_override=material;materials.append(material)
	flame.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;flame.layers=1<<19;add_child(flame)
	for smoke in [false,true]:
		var node:=MultiMeshInstance3D.new();node.name="Smoke" if smoke else "Embers"
		var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.use_custom_data=true
		var mote_quad:=QuadMesh.new();mote_quad.size=Vector2.ONE*(.16 if smoke else .004)
		batch.mesh=mote_quad;batch.instance_count=8 if smoke else 16
		for i in batch.instance_count:
			batch.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(0,.42,0)))
			batch.set_instance_custom_data(i,Color((i+.5)/batch.instance_count,0,0,1))
		batch.custom_aabb=AABB(Vector3(-.4,.4,-.4),Vector3(.8,1.3,.8));node.multimesh=batch
		var mote_material:=ShaderMaterial.new();mote_material.shader=MOTES;mote_material.set_shader_parameter("smoke",smoke)
		node.material_override=mote_material;materials.append(mote_material)
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.layers=1<<19;add_child(node)
	lamp=OmniLight3D.new();lamp.name="Torchlight";lamp.position=Vector3(0,.46,0)
	lamp.light_color=Color("ffb35c");lamp.omni_range=8.0;lamp.omni_attenuation=1.3
	lamp.light_energy=1.65;lamp.shadow_enabled=true;lamp.shadow_bias=.04
	lamp.light_cull_mask=0xfffff;lamp.shadow_caster_mask=0x7ffff;add_child(lamp)
	set_burning(false)
func set_burning(value:bool)->void:
	burning=value;visible=value;set_process(value)
	if lamp!=null:lamp.light_energy=energy() if value else 0.0
func energy()->float:return 1.65+sin(clock*11.7)*.07+sin(clock*19.3+1.2)*.035+sin(clock*4.1)*.05
func advance(delta:float)->void:
	clock=fposmod(clock+delta,3600.0)
	for material in materials:material.set_shader_parameter("clock",clock)
	lamp.light_energy=energy() if burning and is_visible_in_tree() else 0.0
func _process(delta:float)->void:advance(delta)
