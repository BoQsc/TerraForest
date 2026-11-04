# SPDX-License-Identifier: 0BSD
extends SceneTree
const MODEL=preload("res://addons/characters/runtime/assets/Human.r11.glb")
const CARRY=preload("res://addons/characters/runtime/assets/Human.torch.res")
const DURATIONS={"Hold":2.0,"Equip":.45,"Use":1.3}
func _initialize()->void:run.call_deferred()
func run()->void:
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var error:=document.append_from_file("res://addons/characters/authoring/Human.item_use.glb",state)
	if error!=OK:push_error("Item-use GLB decode failed");quit(1);return
	var imported:=document.generate_scene(state,60.0,false,false)
	var model:=MODEL.instantiate();root.add_child(imported);root.add_child(model)
	var source:AnimationPlayer=imported.find_children("*","AnimationPlayer",true,false)[0]
	var target:AnimationPlayer=model.find_children("*","AnimationPlayer",true,false)[0]
	var from:Skeleton3D=imported.find_children("*","Skeleton3D",true,false)[0]
	var to:Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
	var maximum:=0.0
	if from.get_bone_count()!=59 or to.get_bone_count()!=59:push_error("Item-use bone count differs");quit(1);return
	for bone in from.get_bone_count():
		var index:=to.find_bone(from.get_bone_name(bone))
		if index<0:push_error("Unknown item-use bone");quit(1);return
		var difference:=from.get_bone_global_rest(bone).affine_inverse()*to.get_bone_global_rest(index)
		maximum=maxf(maximum,difference.origin.length())
		for axis in 3:maximum=maxf(maximum,(difference.basis[axis]-Basis.IDENTITY[axis]).length())
	if maximum>.0001:push_error("Item-use rest rig differs");quit(1);return
	var skeleton_path:=String(target.get_node(target.root_node).get_path_to(to))
	var library:=AnimationLibrary.new();var records:={}
	for suffix:String in DURATIONS:
		var animation:Animation
		for name in source.get_animation_list():
			if String(name).ends_with("FP_Item_"+suffix):animation=source.get_animation(name).duplicate(true)
		if animation==null or not is_equal_approx(animation.length,DURATIONS[suffix]):push_error("Missing/mistimed item-use clip: "+suffix);quit(1);return
		for track in range(animation.get_track_count()-1,-1,-1):
			var path:=animation.track_get_path(track)
			if path.get_subname_count()!=1 or to.find_bone(path.get_subname(0))<0:
				animation.remove_track(track);continue
			animation.track_set_path(track,NodePath(skeleton_path+":"+path.get_subname(0)))
		var idle:=CARRY.get_animation("FP_Torch_Idle")
		for track in idle.get_track_count():
			if idle.track_get_type(track)!=Animation.TYPE_BLEND_SHAPE:continue
			var index:=animation.add_track(Animation.TYPE_BLEND_SHAPE)
			animation.track_set_path(index,idle.track_get_path(track))
			animation.blend_shape_track_insert_key(index,0,0);animation.blend_shape_track_insert_key(index,animation.length,0)
		animation.resource_name="FP_Item_"+suffix
		animation.loop_mode=Animation.LOOP_LINEAR if suffix=="Hold" else Animation.LOOP_NONE
		library.add_animation(animation.resource_name,animation)
		records[animation.resource_name]={"length":animation.length,"tracks":animation.get_track_count()}
	var metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://addons/characters/authoring/Human.item_use.json"))
	library.set_meta("support_plane_hand_z",metadata.support_plane_hand_z)
	library.set_meta("support_center_hand_y",metadata.support_center_hand_y)
	library.set_meta("approval","Review-only candidate 01; player approval pending")
	error=ResourceSaver.save(library,"res://addons/characters/authoring/Human.item_use.res",ResourceSaver.FLAG_COMPRESS)
	DirAccess.make_dir_recursive_absolute("res://reports/item_use")
	FileAccess.open("res://reports/item_use/import.json",FileAccess.WRITE).store_string(JSON.stringify({"rest_error":maximum,"bones":59,"clips":records,"save_error":error},"  ")+"\n")
	print("ITEM_USE_IMPORT rest_error=",maximum," clips=",records," save=",error)
	imported.free();model.free();quit(0 if error==OK else 1)
