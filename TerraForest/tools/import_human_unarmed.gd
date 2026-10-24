# SPDX-License-Identifier: 0BSD
extends SceneTree
const MODEL = preload("res://addons/characters/runtime/assets/Human.r11.glb")
const PREFIX = "FP_Unarmed_"
const DURATIONS = {"Idle":2.0,"Punch":68.0/60.0}
func find_type(node:Node,type:String)->Node:
	if node.is_class(type):return node
	for child in node.get_children():
		var found:=find_type(child,type)
		if found!=null:return found
	return null
func weight_key(point: Vector3) -> Vector3i:
	return Vector3i((point*100000.0).round())
func repaired_mesh(model: Node, skeleton: Skeleton3D) -> Dictionary:
	var body := model.find_child("Human_Body",true,false) as MeshInstance3D
	assert(body != null and body.skin != null)
	var repair: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://addons/characters/authoring/Human.unarmed.weights.json"))
	var binds := {}
	for i in body.skin.get_bind_count():
		var name := String(body.skin.get_bind_name(i))
		if name.is_empty(): name = String(skeleton.get_bone_name(body.skin.get_bind_bone(i)))
		binds[name] = i
	var lookup := {}; var points: Array[Vector3] = []
	for row: Dictionary in repair.vertices:
		var p := Vector3(row.position[0],row.position[1],row.position[2]); points.append(p)
		lookup[weight_key(p)] = row.weights
	var old := body.mesh; var result := ArrayMesh.new(); result.blend_shape_mode = old.blend_shape_mode
	for i in old.get_blend_shape_count(): result.add_blend_shape(old.get_blend_shape_name(i))
	var changed := 0
	for surface in old.get_surface_count():
		var arrays := old.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var width: int = weights.size()/positions.size()
		for i in positions.size():
			var replacement: Dictionary = lookup.get(weight_key(positions[i]),{})
			if replacement.is_empty():
				for n in points.size():
					if points[n].distance_squared_to(positions[i]) < .000025*.000025:
						replacement = repair.vertices[n].weights; break
			if replacement.is_empty(): continue
			for slot in width: indices[i*width+slot] = 0; weights[i*width+slot] = 0
			var slot := 0
			for name: String in replacement:
				assert(binds.has(name)); indices[i*width+slot] = binds[name]; weights[i*width+slot] = replacement[name]; slot += 1
			changed += 1
		arrays[Mesh.ARRAY_BONES] = indices; arrays[Mesh.ARRAY_WEIGHTS] = weights
		result.add_surface_from_arrays(old.surface_get_primitive_type(surface),arrays,old.surface_get_blend_shape_arrays(surface),{},old.surface_get_format(surface))
		# Runtime reuses the original scene's materials. Saving imported textures
		# from a headless renderer would serialize placeholder texture data.
	assert(changed >= repair.vertices.size(), "Every repaired source vertex must map onto the runtime mesh")
	var error := ResourceSaver.save(result,"res://addons/characters/runtime/assets/Human.unarmed_body.res",ResourceSaver.FLAG_COMPRESS)
	assert(error == OK)
	return {"repaired_runtime_vertices":changed,"source_vertices":repair.vertices.size(),"cross_finger_vertices_before":repair.cross_finger_vertices_before,"surface_count":result.get_surface_count(),"blend_shapes":result.get_blend_shape_count()}
func _initialize()->void:
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var error:=document.append_from_file("res://addons/characters/authoring/Human.unarmed.glb",state)
	if error!=OK:push_error("Unarmed GLB decode failed");quit(1);return
	var imported:=document.generate_scene(state,60.0,false,false)
	var original:=MODEL.instantiate()
	root.add_child(imported);root.add_child(original)
	var source:=find_type(imported,"AnimationPlayer") as AnimationPlayer
	var target:=find_type(original,"AnimationPlayer") as AnimationPlayer
	var from_skeleton:=find_type(imported,"Skeleton3D") as Skeleton3D
	var to_skeleton:=find_type(original,"Skeleton3D") as Skeleton3D
	if source==null or target==null or from_skeleton==null or to_skeleton==null:
		push_error("Unarmed requires the named original rig");quit(1);return
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
	var mesh_report := repaired_mesh(original,to_skeleton)
	print("UNARMED_SKIN ",JSON.stringify(mesh_report))
	var neutral:Animation
	for name in target.get_animation_list():
		if String(name).ends_with("FP_Pickaxe_RightGrip_Idle"):neutral=target.get_animation(name)
	var library:=AnimationLibrary.new();var records:={}
	for suffix in DURATIONS:
		var animation:Animation
		for name in source.get_animation_list():
			if String(name).ends_with(PREFIX+suffix):animation=source.get_animation(name).duplicate(true)
		if animation==null or not is_equal_approx(animation.length,DURATIONS[suffix]):
			push_error("Missing/mistimed unarmed clip: "+suffix);quit(1);return
		for track in range(animation.get_track_count()-1,-1,-1):
			var path:=animation.track_get_path(track)
			if path.get_subname_count()!=1 or to_skeleton.find_bone(path.get_subname(0))<0:
				animation.remove_track(track);continue
			animation.track_set_path(track,NodePath(skeleton_path+":"+path.get_subname(0)))
		# Original pose correctives, including the tool-grip corrective, were
		# fitted to different poses/weights. The repaired hand needs none of them.
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
	error=ResourceSaver.save(library,"res://addons/characters/runtime/assets/Human.unarmed.res",ResourceSaver.FLAG_COMPRESS)
	var report:={"approval":"Reworked after user rejection; visual review pending","rest_error":maximum_error,"bones":59,"original_clips":target.get_animation_list().size(),"actions":records,"skin_repair":mesh_report,"save_error":error,"scope":"Separate empty-hand mesh with repaired finger weights; original rest geometry, materials, bind and other-tool mesh retained. No method events or body integration."}
	DirAccess.make_dir_recursive_absolute("res://reports/unarmed")
	FileAccess.open("res://reports/unarmed/import.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("UNARMED_IMPORT ",JSON.stringify(report))
	imported.free();original.free();quit(0 if error==OK else 1)

