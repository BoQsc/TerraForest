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
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var error:=document.append_from_file("res://addons/characters/authoring/Human.placement.glb",state)
	if error!=OK:push_error("Placement GLB decode failed: "+str(error));quit(1);return
	# Keep constant base-pose tracks, so switching from a tool cannot leave its
	# torso/clavicle pose underneath an otherwise correct hand animation.
	var imported:=document.generate_scene(state,30.0,false,false)
	var original:=MODEL.instantiate()
	root.add_child(imported);root.add_child(original)
	var source:=find_type(imported,"AnimationPlayer") as AnimationPlayer
	var target:=find_type(original,"AnimationPlayer") as AnimationPlayer
	var from_skeleton:=find_type(imported,"Skeleton3D") as Skeleton3D
	var to_skeleton:=find_type(original,"Skeleton3D") as Skeleton3D
	if source==null or target==null or from_skeleton==null or to_skeleton==null:
		push_error("Placement requires the original named rig and animation player");quit(1);return
	var maximum_error:=0.0
	for bone in from_skeleton.get_bone_count():
		var target_bone:=to_skeleton.find_bone(from_skeleton.get_bone_name(bone))
		if target_bone<0:push_error("Missing R11 bone");quit(1);return
		var difference:Transform3D=from_skeleton.get_bone_global_rest(bone).affine_inverse()*to_skeleton.get_bone_global_rest(target_bone)
		maximum_error=maxf(maximum_error,difference.origin.length())
		for axis in 3:maximum_error=maxf(maximum_error,(difference.basis[axis]-Basis.IDENTITY[axis]).length())
	if from_skeleton.get_bone_count()!=59 or maximum_error>0.0001:
		push_error("Placement rest rig differs from R11: "+str(maximum_error));quit(1);return
	var animation:Animation
	for name in source.get_animation_list():
		if String(name).ends_with("FP_Place_Relaxed"):animation=source.get_animation(name).duplicate(true)
	if animation==null:push_error("Placement action missing: "+str(source.get_animation_list()));quit(1);return
	var skeleton_path:=String(target.get_node(target.root_node).get_path_to(to_skeleton))
	for track in range(animation.get_track_count()-1,-1,-1):
		var path:=animation.track_get_path(track)
		if path.get_subname_count()!=1 or to_skeleton.find_bone(path.get_subname(0))<0:
			animation.remove_track(track);continue
		animation.track_set_path(track,NodePath(skeleton_path+":"+path.get_subname(0)))
	animation.resource_name="FP_Place_Relaxed"
	animation.loop_mode=Animation.LOOP_NONE
	var library:=AnimationLibrary.new();library.add_animation("FP_Place_Relaxed",animation)
	error=ResourceSaver.save(library,"res://addons/characters/runtime/assets/Human.placement.res",ResourceSaver.FLAG_COMPRESS)
	var report:={"rest_error":maximum_error,"bones":59,"original_clips":target.get_animation_list().size(),"track_count":animation.get_track_count(),"duration":animation.length,"skeleton_path":skeleton_path,"save_error":error,"scope":"Blender-authored bone tracks remapped onto the unchanged R11 runtime skeleton; no method, audio, object or gameplay-event tracks."}
	DirAccess.make_dir_recursive_absolute("res://reports/human_placement")
	FileAccess.open("res://reports/human_placement/import.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("HUMAN_PLACEMENT_IMPORT ",JSON.stringify(report))
	imported.free();original.free();quit(0 if error==OK else 1)
