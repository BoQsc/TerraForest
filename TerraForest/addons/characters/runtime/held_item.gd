# SPDX-License-Identifier: 0BSD
extends MeshInstance3D
## One reused hand attachment. Existing consumable art; universal visual fallback.
const MESHES={214:preload("res://addons/player_runtime/art/consumables/214.res"),215:preload("res://addons/player_runtime/art/consumables/215.res"),216:preload("res://addons/player_runtime/art/consumables/216.res"),217:preload("res://addons/player_runtime/art/consumables/217.res"),218:preload("res://addons/player_runtime/art/consumables/218.res"),219:preload("res://addons/player_runtime/art/consumables/219.res")}
static var mounts:Dictionary={}
var configured_item:=-1
var fallback:BoxMesh
static func supports(item:int)->bool:
	return item>0 and item not in [1,2,3,4,5,6,7,8] and not (item>=401 and item<=411)
func _init()->void:
	name="Equipment_Generic_Item";set_meta("first_person_equipment",true)
	fallback=BoxMesh.new();fallback.size=Vector3(.10,.08,.12)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("718e9e");material.roughness=.88;fallback.material=material
	mesh=fallback
	if mounts.is_empty():mounts=JSON.parse_string(FileAccess.get_file_as_string("res://addons/characters/runtime/assets/Item_hold.mounts.json"))
func configure(item:int,shown:bool)->void:
	visible=shown and supports(item)
	if not visible or configured_item==item:return
	configured_item=item;mesh=MESHES.get(item,fallback)
	basis=Basis(Vector3.RIGHT,Vector3(0,0,-1),Vector3(0,1,0))
	position=Vector3(0,mounts.support_center_hand_y,-float(mounts.heights.get(str(item),mounts.heights.fallback)))
