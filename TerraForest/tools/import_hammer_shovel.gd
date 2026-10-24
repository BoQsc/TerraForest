# SPDX-License-Identifier: 0BSD
extends SceneTree
const MODEL=preload("res://addons/characters/runtime/assets/Human.r11.glb")
func find_type(node:Node,type:String)->Node:
	if node.is_class(type):return node
	for child in node.get_children():
		var found:=find_type(child,type)
		if found!=null:return found
	return null
func _initialize()->void:
	var original:=MODEL.instantiate();root.add_child(original)
	var target:=find_type(original,"AnimationPlayer") as AnimationPlayer
	var skeleton:=find_type(original,"Skeleton3D") as Skeleton3D
	var neutral:Animation
	for name in target.get_animation_list():
		if String(name).ends_with("FP_Pickaxe_RightGrip_Idle"):neutral=target.get_animation(name)
	var records:={}
	for kind:String in ["hammer","shovel"]:
		var document:=GLTFDocument.new();var state:=GLTFState.new()
		if document.append_from_file("res://addons/characters/authoring/Human.%s.glb"%kind,state)!=OK:
			push_error("Cannot decode "+kind);original.free();quit(1);return
		var imported:=document.generate_scene(state,60.0,false,false);root.add_child(imported)
		var source:=find_type(imported,"AnimationPlayer") as AnimationPlayer
		var from_skeleton:=find_type(imported,"Skeleton3D") as Skeleton3D
		var rest_error:=0.0
		if source==null or from_skeleton==null or from_skeleton.get_bone_count()!=skeleton.get_bone_count():
			push_error("R11 skeleton missing/different");imported.free();original.free();quit(1);return
		for bone in from_skeleton.get_bone_count():
			var index:=skeleton.find_bone(from_skeleton.get_bone_name(bone))
			if index<0:push_error("R11 bone missing");imported.free();original.free();quit(1);return
			var difference:Transform3D=from_skeleton.get_bone_global_rest(bone).affine_inverse()*skeleton.get_bone_global_rest(index)
			rest_error=maxf(rest_error,difference.origin.length())
			for axis in 3:rest_error=maxf(rest_error,(difference.basis[axis]-Basis.IDENTITY[axis]).length())
		if rest_error>.0001:push_error("R11 rest differs");imported.free();original.free();quit(1);return
		var library:=AnimationLibrary.new()
		var prefix:="FP_"+kind.capitalize()+"_"
		var durations:={"Idle":3.0,"Walk":1.0,"Run":.8,"Jump":1.5,"Swing":1.0 if kind=="hammer" else 1.4}
		var skeleton_path:=String(target.get_node(target.root_node).get_path_to(skeleton))
		var clips:={}
		for suffix:String in durations:
			var animation:Animation
			for name in source.get_animation_list():
				if String(name).ends_with(prefix+suffix):animation=source.get_animation(name).duplicate(true)
			if animation==null or not is_equal_approx(animation.length,durations[suffix]):
				push_error("Missing/mistimed "+prefix+suffix);imported.free();original.free();quit(1);return
			for track in range(animation.get_track_count()-1,-1,-1):
				var path:=animation.track_get_path(track)
				if animation.track_get_type(track) not in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D] or path.get_subname_count()!=1 or skeleton.find_bone(path.get_subname(0))<0:
					animation.remove_track(track);continue
				animation.track_set_path(track,NodePath(skeleton_path+":"+path.get_subname(0)))
			# Old corrective morphs belong to the old poses. Clear them on entry.
			for track in neutral.get_track_count():
				if neutral.track_get_type(track)!=Animation.TYPE_BLEND_SHAPE:continue
				var index:=animation.add_track(Animation.TYPE_BLEND_SHAPE)
				animation.track_set_path(index,neutral.track_get_path(track))
				animation.blend_shape_track_insert_key(index,0,0)
				animation.blend_shape_track_insert_key(index,animation.length,0)
			animation.resource_name=prefix+suffix
			animation.loop_mode=Animation.LOOP_LINEAR if suffix in ["Idle","Walk","Run"] else Animation.LOOP_NONE
			library.add_animation(prefix+suffix,animation)
			clips[prefix+suffix]={"duration":animation.length,"tracks":animation.get_track_count()}
		var error:=ResourceSaver.save(library,"res://addons/characters/runtime/assets/Human.%s.res"%kind,ResourceSaver.FLAG_COMPRESS)
		records[kind]={"rest_error":rest_error,"bones":skeleton.get_bone_count(),"clips":clips,"save_error":error}
		imported.free()
		if error!=OK:push_error("Cannot save "+kind);original.free();quit(1);return
	DirAccess.make_dir_recursive_absolute("res://reports/hammer_shovel")
	FileAccess.open("res://reports/hammer_shovel/import.json",FileAccess.WRITE).store_string(JSON.stringify(records,"  ")+"\n")
	print("HAMMER_SHOVEL_IMPORT ",JSON.stringify(records));original.free();quit()
