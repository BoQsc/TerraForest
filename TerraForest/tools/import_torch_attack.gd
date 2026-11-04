# SPDX-License-Identifier: 0BSD
extends SceneTree
const MODEL=preload("res://addons/characters/runtime/assets/Human.r11.glb")
const CARRY=preload("res://addons/characters/runtime/assets/Human.torch.res")
const OUTPUT="res://addons/characters/authoring/Human.torch_attack.res"
func _initialize()->void:run.call_deferred()
func run()->void:
	if OS.get_cmdline_user_args().has("--promote-approved-first-person"):
		# Promotion copies the reviewed library byte-for-byte. Regenerating a GLB
		# is a separate authoring operation and cannot silently replace approval.
		var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence/torch_attack/revision02/evidence.json"))
		var expected:String=evidence.sha256["addons/characters/authoring/Human.torch_attack.res"]
		if FileAccess.get_sha256(OUTPUT)!=expected:push_error("Torch candidate differs from reviewed revision 02");quit(1);return
		var target_path:="res://addons/characters/runtime/assets/Human.torch_attack.res"
		var copy_error:=DirAccess.copy_absolute(ProjectSettings.globalize_path(OUTPUT),ProjectSettings.globalize_path(target_path))
		print("TORCH_ATTACK_PROMOTE error=",copy_error," sha256=",FileAccess.get_sha256(target_path))
		quit(0 if copy_error==OK else 1);return
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var error:=document.append_from_file("res://addons/characters/authoring/Human.torch_attack.glb",state)
	if error!=OK:push_error("Torch attack decode failed");quit(1);return
	var imported:=document.generate_scene(state,60.0,false,false)
	var model:=MODEL.instantiate();root.add_child(imported);root.add_child(model)
	var source:AnimationPlayer=imported.find_children("*","AnimationPlayer",true,false)[0]
	var target:AnimationPlayer=model.find_children("*","AnimationPlayer",true,false)[0]
	var from:Skeleton3D=imported.find_children("*","Skeleton3D",true,false)[0]
	var to:Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
	var maximum:=0.0
	if from.get_bone_count()!=to.get_bone_count():push_error("Bone count differs");quit(1);return
	for bone in from.get_bone_count():
		var index:=to.find_bone(from.get_bone_name(bone))
		if index<0:push_error("Unknown bone");quit(1);return
		var difference:=from.get_bone_global_rest(bone).affine_inverse()*to.get_bone_global_rest(index)
		maximum=maxf(maximum,difference.origin.length())
		for axis in 3:maximum=maxf(maximum,(difference.basis[axis]-Basis.IDENTITY[axis]).length())
	if maximum>.0001:push_error("Rest rig differs");quit(1);return
	var animation:Animation
	for name in source.get_animation_list():
		if String(name).ends_with("FP_Torch_Swing"):animation=source.get_animation(name).duplicate(true)
	if animation==null or not is_equal_approx(animation.length,1.1):push_error("Missing/mistimed strike");quit(1);return
	var skeleton_path:=String(target.get_node(target.root_node).get_path_to(to))
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
		animation.blend_shape_track_insert_key(index,0,0)
		animation.blend_shape_track_insert_key(index,animation.length,0)
	animation.resource_name="FP_Torch_Swing";animation.loop_mode=Animation.LOOP_NONE
	var library:=AnimationLibrary.new();library.add_animation("FP_Torch_Swing",animation)
	library.set_meta("approval","Candidate: player visual review pending")
	library.set_meta("proposed_contact_seconds",26.0/60.0)
	error=ResourceSaver.save(library,OUTPUT,ResourceSaver.FLAG_COMPRESS)
	print("TORCH_ATTACK_IMPORT rest_error=",maximum," bones=",to.get_bone_count()," duration=",animation.length," tracks=",animation.get_track_count()," save=",error)
	imported.free();model.free();quit(0 if error==OK else 1)
