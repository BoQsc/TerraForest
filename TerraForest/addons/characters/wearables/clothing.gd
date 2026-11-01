# SPDX-License-Identifier: 0BSD
extends Node
## Presentation of existing inventory IDs. Owns no inventory or animation state.
const ITEMS={301:preload("res://addons/characters/wearables/woven/301.res"),302:preload("res://addons/characters/wearables/woven/302.res"),303:preload("res://addons/characters/wearables/woven/303.res")}
var worn:=PackedInt32Array([0,0,0])
var garments:Dictionary={}
var covered:Array[Dictionary]=[]
var third_person:=true
var ready_to_wear:=false

func prepare(model:Node3D)->bool:
	if ready_to_wear:return true
	var skeletons:=model.find_children("*","Skeleton3D",true,false)
	if skeletons.is_empty():return false
	var rig:Skeleton3D=skeletons[0]
	var names:Array=ITEMS[301].get_meta("bone_names")
	var skin:=Skin.new()
	for name:String in names:
		var index:=rig.find_bone(name)
		if index<0:push_error("Clothing rig is missing "+name);return false
		skin.add_named_bind(name,rig.get_bone_global_rest(index).affine_inverse())
	for node:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		var name:=String(node.name)
		var item:=302 if name=="Wardrobe_FieldVest" or name.begins_with("Carry_") or name.begins_with("Carry.") else (303 if name=="Wardrobe_Boots" else (301 if name.begins_with("Hair_") or name.begins_with("Hair.") else 0))
		if item:covered.append({"node":node,"visible":node.visible,"item":item})
	for id:int in ITEMS:
		var instance:=MeshInstance3D.new();instance.name="Woven_%d"%id;instance.mesh=ITEMS[id];instance.skin=skin
		instance.layers=1<<19;rig.add_child(instance);instance.skeleton=instance.get_path_to(rig);garments[id]=instance
	ready_to_wear=true;refresh_visibility();return true

func set_slots(slots:Array)->bool:
	var selected:=PackedInt32Array([0,0,0])
	for i in mini(3,slots.size()):
		if int(slots[i].get("item",0))==301+i and int(slots[i].get("count",0))>0:selected[i]=301+i
	if worn==selected:return false
	worn=selected;refresh_visibility();return true

func set_third_person(value:bool)->void:
	third_person=value;refresh_visibility()

func refresh_visibility()->void:
	if not ready_to_wear:return
	for id:int in garments:
		var mesh:MeshInstance3D=garments[id]
		mesh.visible=id in worn and (id!=301 or third_person)
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if third_person else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for original:Dictionary in covered:
		original.node.visible=original.visible and original.item not in worn and (original.item!=301 or third_person)
