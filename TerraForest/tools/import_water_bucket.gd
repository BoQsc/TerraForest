# SPDX-License-Identifier: 0BSD
extends SceneTree
const MODEL = preload("res://addons/characters/runtime/assets/Human.r11.glb")
const PREFIX = "FP_Bucket_"
const DURATIONS = {"Idle":2.0,"Walk":1.0,"Run":0.8,"Jump":1.5,"Scoop":2.4,"Pour":2.8}
func find_type(node:Node,type:String)->Node:
	if node.is_class(type):return node
	for child in node.get_children():
		var found:=find_type(child,type)
		if found!=null:return found
	return null
func _initialize()->void:
	run.call_deferred()
func run()->void:
	if not import_mesh():quit(1);return
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var error:=document.append_from_file("res://addons/characters/authoring/Human.bucket.glb",state)
	if error!=OK:push_error("Bucket GLB decode failed");quit(1);return
	var imported:=document.generate_scene(state,60.0,false,false)
	var original:=MODEL.instantiate()
	root.add_child(imported);root.add_child(original)
	var source:=find_type(imported,"AnimationPlayer") as AnimationPlayer
	var target:=find_type(original,"AnimationPlayer") as AnimationPlayer
	var from_skeleton:=find_type(imported,"Skeleton3D") as Skeleton3D
	var to_skeleton:=find_type(original,"Skeleton3D") as Skeleton3D
	if source==null or target==null or from_skeleton==null or to_skeleton==null:
		push_error("Bucket requires the named original rig");quit(1);return
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
			push_error("Missing/mistimed bucket clip: "+suffix);quit(1);return
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
	error=ResourceSaver.save(library,"res://addons/characters/runtime/assets/Human.bucket.res",ResourceSaver.FLAG_COMPRESS)
	var report:={"approval":"Bucket appearance awaiting review","rest_error":maximum_error,"bones":59,"original_clips":target.get_animation_list().size(),"actions":records,"save_error":error,"scope":"Blender bone animation on unchanged R11 runtime model; clears original pose-specific morph correctives; no methods, gameplay events, root motion or body integration."}
	DirAccess.make_dir_recursive_absolute("res://reports/water_bucket_visuals")
	FileAccess.open("res://reports/water_bucket_visuals/import.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("BUCKET_IMPORT ",JSON.stringify(report))
	imported.free();original.free();quit(0 if error==OK else 1)

func import_mesh()->bool:
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	if document.append_from_file("res://addons/characters/authoring/Bucket.glb",state)!=OK:return false
	var scene:=document.generate_scene(state)
	root.add_child(scene)
	var held:=ArrayMesh.new();var bail:=ArrayMesh.new();var pickup:=ArrayMesh.new()
	var nodes:=scene.find_children("*","MeshInstance3D",true,false)
	if nodes.size()!=2:scene.free();return false
	for node:MeshInstance3D in nodes:
		var part:="bail" if String(node.name).to_lower().contains("bail") else "pail"
		for surface in node.mesh.get_surface_count():
			for target in [bail if part=="bail" else held,pickup]:
				var surface_tool:=SurfaceTool.new()
				var at:=node.global_transform
				if target==pickup:at.origin+=Vector3(0,.22,0)
				surface_tool.append_from(node.mesh,surface,at)
				surface_tool.set_material(node.mesh.surface_get_material(surface))
				surface_tool.commit(target)
	var flags:=ResourceSaver.FLAG_COMPRESS|ResourceSaver.FLAG_BUNDLE_RESOURCES
	var error:=ResourceSaver.save(held,"res://addons/volumetric_water/assets/Bucket.held.res",flags)
	error=error|ResourceSaver.save(bail,"res://addons/volumetric_water/assets/Bucket.bail.res",flags)
	error=error|ResourceSaver.save(pickup,"res://addons/volumetric_water/assets/Bucket.pickup.res",flags)
	scene.free();return error==OK
