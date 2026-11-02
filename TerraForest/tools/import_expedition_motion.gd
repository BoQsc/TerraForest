# SPDX-License-Identifier: 0BSD
extends "res://tools/import_human_placement.gd"

func _initialize()->void:
	var zombie:=OS.get_cmdline_user_args().has("--zombie")
	var source_path:="res://addons/characters/authoring/Zombie.alert.glb" if zombie else "res://reviews/player_wakeup/Human.wakeup.glb"
	var target_path:="res://addons/characters/runtime/assets/Zombie.alert.res" if zombie else "res://reviews/player_wakeup/Human.wakeup.res"
	var clip:="Zombie_Alert_Walk" if zombie else "FP_Wake_Confused_Review"
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	if document.append_from_file(source_path,state)!=OK:quit(1);return
	var imported:=document.generate_scene(state,60 if zombie else 30,false,false)
	var original:Node=load("res://addons/characters/runtime/assets/Zombie.r4.glb").instantiate() if zombie else MODEL.instantiate()
	root.add_child(imported);root.add_child(original)
	var source:AnimationPlayer=find_type(imported,"AnimationPlayer")
	var target:AnimationPlayer=find_type(original,"AnimationPlayer")
	var from_skeleton:Skeleton3D=find_type(imported,"Skeleton3D")
	var to_skeleton:Skeleton3D=find_type(original,"Skeleton3D")
	var difference_max:=0.0
	for bone in from_skeleton.get_bone_count():
		var target_bone:=to_skeleton.find_bone(from_skeleton.get_bone_name(bone))
		if target_bone<0:quit(1);return
		var difference:=from_skeleton.get_bone_global_rest(bone).affine_inverse()*to_skeleton.get_bone_global_rest(target_bone)
		difference_max=maxf(difference_max,difference.origin.length())
		for axis in 3:difference_max=maxf(difference_max,(difference.basis[axis]-Basis.IDENTITY[axis]).length())
	if from_skeleton.get_bone_count()!=59 or difference_max>.0001:push_error("Rest rig changed");quit(1);return
	var animation:Animation
	for name in source.get_animation_list():
		if String(name).ends_with(clip):animation=source.get_animation(name).duplicate(true)
	if animation==null:push_error("Motion missing");quit(1);return
	var skeleton_path:=String(target.get_node(target.root_node).get_path_to(to_skeleton))
	for track in range(animation.get_track_count()-1,-1,-1):
		var path:=animation.track_get_path(track)
		if path.get_subname_count()!=1 or to_skeleton.find_bone(path.get_subname(0))<0:animation.remove_track(track);continue
		animation.track_set_path(track,NodePath(skeleton_path+":"+path.get_subname(0)))
	if zombie:
		var reference:Animation=preload("res://addons/characters/runtime/assets/Zombie.drag_walk.res").get_animation("Zombie_Walk_Drag_Right")
		for track in reference.get_track_count():
			if reference.track_get_type(track)!=Animation.TYPE_BLEND_SHAPE:continue
			var added:=animation.add_track(Animation.TYPE_BLEND_SHAPE);animation.track_set_path(added,reference.track_get_path(track))
			animation.track_insert_key(added,0.0,0.0);animation.track_insert_key(added,animation.length,0.0)
	animation.resource_name=clip;animation.loop_mode=Animation.LOOP_LINEAR if zombie else Animation.LOOP_NONE
	var library:=AnimationLibrary.new();library.add_animation(clip,animation)
	var error:=ResourceSaver.save(library,target_path,ResourceSaver.FLAG_COMPRESS)
	print("EXPEDITION_MOTION_IMPORT ",{"clip":clip,"bones":59,"rest_error":difference_max,"duration":animation.length,"tracks":animation.get_track_count(),"save_error":error})
	imported.free();original.free();quit(0 if error==OK else 1)
