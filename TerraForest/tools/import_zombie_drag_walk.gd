# SPDX-License-Identifier: 0BSD
extends SceneTree
const MODEL=preload("res://addons/characters/runtime/assets/Zombie.r4.glb")
func find_type(node:Node,type:String)->Node:
	if node.is_class(type):return node
	for child in node.get_children():
		var found:=find_type(child,type)
		if found!=null:return found
	return null
func _initialize()->void:
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var error:=document.append_from_file("res://addons/characters/authoring/Zombie.drag_walk.glb",state)
	if error!=OK:push_error("Drag walk GLB rejected");quit(1);return
	var imported:=document.generate_scene(state,60.0,false,false)
	var original:=MODEL.instantiate();root.add_child(imported);root.add_child(original)
	var source:=find_type(imported,"AnimationPlayer") as AnimationPlayer
	var target:=find_type(original,"AnimationPlayer") as AnimationPlayer
	var from_skeleton:=find_type(imported,"Skeleton3D") as Skeleton3D
	var to_skeleton:=find_type(original,"Skeleton3D") as Skeleton3D
	if source==null or target==null or from_skeleton==null or to_skeleton==null:
		push_error("Drag walk rig is missing");quit(1);return
	var rest_error:=0.0
	for bone in from_skeleton.get_bone_count():
		var target_bone:=to_skeleton.find_bone(from_skeleton.get_bone_name(bone))
		if target_bone<0:push_error("Missing original zombie bone");quit(1);return
		var difference:Transform3D=from_skeleton.get_bone_global_rest(bone).affine_inverse()*to_skeleton.get_bone_global_rest(target_bone)
		rest_error=maxf(rest_error,difference.origin.length())
		for axis in 3:rest_error=maxf(rest_error,(difference.basis[axis]-Basis.IDENTITY[axis]).length())
	if from_skeleton.get_bone_count()!=59 or rest_error>.0001:
		push_error("Drag walk bind pose differs: "+str(rest_error));quit(1);return
	var animation:Animation
	var walk:Animation
	for name in source.get_animation_list():
		if String(name).ends_with("Zombie_Walk_Drag_Right"):animation=source.get_animation(name).duplicate(true)
	for name in target.get_animation_list():
		if String(name).ends_with("Zombie_Walk"):walk=target.get_animation(name)
	if animation==null or walk==null:push_error("Zombie walk action missing");quit(1);return
	var skeleton_path:=String(target.get_node(target.root_node).get_path_to(to_skeleton))
	for track in range(animation.get_track_count()-1,-1,-1):
		var path:=animation.track_get_path(track)
		if path.get_subname_count()!=1 or to_skeleton.find_bone(path.get_subname(0))<0:
			animation.remove_track(track);continue
		animation.track_set_path(track,NodePath(skeleton_path+":"+path.get_subname(0)))
	var morph_resets:=0
	# R4 attacks deform mouth/knees/clothing. Carry the original walk's neutral
	# morph channels into the new action so no previous strike shape is retained.
	for track in walk.get_track_count():
		if walk.track_get_type(track)!=Animation.TYPE_BLEND_SHAPE:continue
		var added:=animation.add_track(Animation.TYPE_BLEND_SHAPE)
		animation.track_set_path(added,walk.track_get_path(track))
		animation.track_insert_key(added,0.0,0.0);animation.track_insert_key(added,animation.length,0.0)
		morph_resets+=1
	animation.resource_name="Zombie_Walk_Drag_Right";animation.loop_mode=Animation.LOOP_LINEAR
	var library:=AnimationLibrary.new();library.add_animation("Zombie_Walk_Drag_Right",animation)
	error=ResourceSaver.save(library,"res://addons/characters/runtime/assets/Zombie.drag_walk.res",ResourceSaver.FLAG_COMPRESS)
	DirAccess.make_dir_recursive_absolute("res://reports/zombie_drag_walk")
	var report:={"bones":59,"rest_error":rest_error,"original_clips":target.get_animation_list().size(),"tracks":animation.get_track_count(),"neutral_morph_tracks":morph_resets,"seconds":animation.length,"save_error":error}
	FileAccess.open("res://reports/zombie_drag_walk/import.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ZOMBIE_DRAG_IMPORT ",JSON.stringify(report));imported.free();original.free();quit(0 if error==OK else 1)
