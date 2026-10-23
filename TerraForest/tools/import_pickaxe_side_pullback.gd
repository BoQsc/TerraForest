# SPDX-License-Identifier: 0BSD
extends SceneTree
const MODEL = preload("res://addons/characters/runtime/assets/Human.r11.glb")
const PREFIX = "FP_Pickaxe_SidePullback_"
const DURATIONS = {"Swing":1.2}
func find_type(node:Node,type:String)->Node:
	if node.is_class(type):return node
	for child in node.get_children():
		var found:=find_type(child,type)
		if found!=null:return found
	return null
func _initialize()->void:
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var error:=document.append_from_file("res://addons/characters/authoring/Human.pickaxe_side_pullback.glb",state)
	if error!=OK:push_error("Diagonal pickaxe GLB decode failed");quit(1);return
	var imported:=document.generate_scene(state,60.0,false,false)
	var original:=MODEL.instantiate()
	root.add_child(imported);root.add_child(original)
	var source:=find_type(imported,"AnimationPlayer") as AnimationPlayer
	var target:=find_type(original,"AnimationPlayer") as AnimationPlayer
	var from_skeleton:=find_type(imported,"Skeleton3D") as Skeleton3D
	var to_skeleton:=find_type(original,"Skeleton3D") as Skeleton3D
	if source==null or target==null or from_skeleton==null or to_skeleton==null:
		push_error("Diagonal pickaxe requires the named original rig");quit(1);return
	var maximum_error:=0.0
	for bone in from_skeleton.get_bone_count():
		var index:=to_skeleton.find_bone(from_skeleton.get_bone_name(bone))
		if index<0:push_error("Missing R11 bone");quit(1);return
		var difference:Transform3D=from_skeleton.get_bone_global_rest(bone).affine_inverse()*to_skeleton.get_bone_global_rest(index)
		maximum_error=maxf(maximum_error,difference.origin.length())
		for axis in 3:maximum_error=maxf(maximum_error,(difference.basis[axis]-Basis.IDENTITY[axis]).length())
	if from_skeleton.get_bone_count()!=59 or maximum_error>0.0001:
		push_error("R11 rest rig differs: "+str(maximum_error));quit(1);return
	var skeleton_path:=String(target.get_node(target.root_node).get_path_to(to_skeleton))
	var neutral:Animation
	for name in target.get_animation_list():
		if String(name).ends_with("FP_Pickaxe_RightGrip_Idle"):neutral=target.get_animation(name)
	var library:=AnimationLibrary.new();var records:={}
	for suffix in DURATIONS:
		var animation:Animation
		for name in source.get_animation_list():
			if String(name).ends_with(PREFIX+suffix):animation=source.get_animation(name).duplicate(true)
		if animation==null or not is_equal_approx(animation.length,DURATIONS[suffix]):
			push_error("Missing/mistimed pickaxe clip: "+suffix);quit(1);return
		for track in range(animation.get_track_count()-1,-1,-1):
			var path:=animation.track_get_path(track)
			if path.get_subname_count()!=1 or to_skeleton.find_bone(path.get_subname(0))<0:
				animation.remove_track(track);continue
			animation.track_set_path(track,NodePath(skeleton_path+":"+path.get_subname(0)))
		# Original pose-specific body/sleeve correctives were fitted to a different
		# arm pose. Reset those weights rather than deforming the new grip with
		# them. Keep the source track paths, with no arbitrary property tracks.
		var morphs:=0
		if neutral!=null:
			for track in neutral.get_track_count():
				if neutral.track_get_type(track)!=Animation.TYPE_BLEND_SHAPE:continue
				var index:=animation.add_track(Animation.TYPE_BLEND_SHAPE)
				animation.track_set_path(index,neutral.track_get_path(track))
				var value:=0.0
				animation.blend_shape_track_insert_key(index,0.0,value)
				animation.blend_shape_track_insert_key(index,animation.length,value)
				morphs+=1
		animation.resource_name=PREFIX+suffix
		animation.loop_mode=Animation.LOOP_LINEAR if suffix in ["Idle","Walk","Run"] else Animation.LOOP_NONE
		library.add_animation(PREFIX+suffix,animation)
		records[PREFIX+suffix]={"duration":animation.length,"tracks":animation.get_track_count(),"neutral_morphs":morphs,"loop":animation.loop_mode}
	error=ResourceSaver.save(library,"res://addons/characters/runtime/assets/Human.pickaxe_side_pullback.res",ResourceSaver.FLAG_COMPRESS)
	var report:={"approval":"PENDING USER VISUAL REVIEW; do not commit","rest_error":maximum_error,"bones":59,"original_clips":target.get_animation_list().size(),"actions":records,"save_error":error,"scope":"Blender bone animation on unchanged R11 runtime model; clears original pose-specific morph correctives; no methods, gameplay events, root motion or body integration."}
	DirAccess.make_dir_recursive_absolute("res://reports/pickaxe_side_pullback")
	FileAccess.open("res://reports/pickaxe_side_pullback/import.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PICKAXE_SIDE_PULLBACK_IMPORT ",JSON.stringify(report))
	imported.free();original.free();quit(0 if error==OK else 1)
