extends SceneTree

const MODEL_PATH="res://addons/characters/runtime/assets/Human.r11.glb"
const UNARMED_PATH="res://addons/characters/runtime/assets/Human.unarmed_body.res"
const OUTPUT="res://addons/characters/runtime/assets/first_person"
const RECIPE="res://tools/bake_first_person_meshes.gd"

func _initialize()->void:run.call_deferred()

func subset(values:Variant,vertices:PackedInt32Array,stride:int)->Variant:
	if values==null:return null
	var result:Variant=values.slice(0,0)
	for vertex in vertices:
		for component in stride:result.append(values[vertex*stride+component])
	return result

func slice_arrays(source:Array,vertices:PackedInt32Array,count:int)->Array:
	var result:Array=[];result.resize(Mesh.ARRAY_MAX)
	for channel in Mesh.ARRAY_INDEX:
		if source[channel]!=null and not source[channel].is_empty():
			result[channel]=subset(source[channel],vertices,source[channel].size()/count)
	return result

func changes_shape(morph:Array,base:Array)->bool:
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT]:
		if morph[channel]==null:continue
		for index in morph[channel].size():
			if channel==Mesh.ARRAY_TANGENT:
				if absf(morph[channel][index]-base[channel][index])>.001:return true
			elif morph[channel][index].distance_squared_to(base[channel][index])>(0.0000000001 if channel==Mesh.ARRAY_VERTEX else .000001):return true
	return false

func split_mesh(source:ArrayMesh,skin:Skin,skeleton:Skeleton3D,arms:bool)->ArrayMesh:
	var surfaces:Array=[]
	var relevant:={}
	for surface in source.get_surface_count():
		var arrays:=source.surface_get_arrays(surface)
		var count:int=arrays[Mesh.ARRAY_VERTEX].size()
		var arm_weights:PackedFloat32Array=[];arm_weights.resize(count)
		var influences:int=arrays[Mesh.ARRAY_BONES].size()/count
		for vertex in count:
			for influence in influences:
				var bind:int=arrays[Mesh.ARRAY_BONES][vertex*influences+influence]
				var bone:=skeleton.find_bone(skin.get_bind_name(bind))
				if bone<0:bone=skin.get_bind_bone(bind)
				var label:=String(skeleton.get_bone_name(bone))
				if "Arm" in label or "Hand" in label:
					arm_weights[vertex]+=arrays[Mesh.ARRAY_WEIGHTS][vertex*influences+influence]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var selected:PackedInt32Array=[]
		for triangle in range(0,indices.size(),3):
			var weight:float=(arm_weights[indices[triangle]]+arm_weights[indices[triangle+1]]+arm_weights[indices[triangle+2]])/3.0
			if (weight>=.5)==arms:selected.append_array(indices.slice(triangle,triangle+3))
		if selected.is_empty():
			if arms:continue
			selected=PackedInt32Array([0,0,0])
		var vertices:PackedInt32Array=[];var lookup:={};var remapped:PackedInt32Array=[]
		for index in selected:
			if not lookup.has(index):lookup[index]=vertices.size();vertices.append(index)
			remapped.append(lookup[index])
		var output:=slice_arrays(arrays,vertices,count);output[Mesh.ARRAY_INDEX]=remapped
		var blends:Array=[]
		var source_blends:=source.surface_get_blend_shape_arrays(surface)
		for shape in source.get_blend_shape_count():
			var morph:=slice_arrays(source_blends[shape],vertices,count)
			blends.append(morph)
			if not arms:relevant[shape]=true;continue
			if changes_shape(morph,output):relevant[shape]=true
		surfaces.append({"arrays":output,"blends":blends,"vertices":vertices,"source":surface,"flags":source.surface_get_format(surface)})
	var mesh:=ArrayMesh.new();mesh.blend_shape_mode=source.blend_shape_mode
	var channels:PackedInt32Array=[]
	for shape in source.get_blend_shape_count():
		if relevant.has(shape):mesh.add_blend_shape(source.get_blend_shape_name(shape));channels.append(shape)
	var surface_map:PackedInt32Array=[]
	var vertex_map:Array=[]
	for surface:Dictionary in surfaces:
		var blends:Array[Array]=[]
		for shape in channels:blends.append(surface.blends[shape])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface.arrays,blends,{},surface.flags)
		surface_map.append(surface.source)
		vertex_map.append(surface.vertices)
	mesh.set_meta("source_surfaces",surface_map);mesh.set_meta("source_blend_shapes",channels)
	mesh.set_meta("source_vertices",vertex_map)
	return mesh

func run()->void:
	var sources:={}
	for path in [MODEL_PATH,MODEL_PATH+".import",UNARMED_PATH,RECIPE]:sources[path]=FileAccess.get_sha256(path)
	var receipt:=OUTPUT.path_join("bake.json")
	if FileAccess.file_exists(receipt):
		var previous:Variant=JSON.parse_string(FileAccess.get_file_as_string(receipt))
		var current:bool=previous is Dictionary and previous.get("sources")==sources
		if current:
			for path in previous.get("outputs",{}):
				if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=previous.outputs[path]:current=false;break
		if current:print("FIRST_PERSON_MESHES current");quit();return
	if "--check-only" in OS.get_cmdline_user_args():push_error("First-person mesh bake is stale");quit(1);return
	var model:Node3D=load(MODEL_PATH).instantiate();root.add_child(model)
	var skeleton:Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
	var outputs:={};var counts:={}
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for entry in [["body","Human_Body"],["unarmed","Human_Body"],["shirt","Wardrobe_WorkShirt"]]:
		var node:MeshInstance3D=model.find_child(entry[1],true,false)
		var source:ArrayMesh=load(UNARMED_PATH).duplicate() if entry[0]=="unarmed" else node.mesh
		if entry[0]=="unarmed":
			for surface in source.get_surface_count():source.surface_set_material(surface,node.mesh.surface_get_material(surface))
		for arms in [false,true]:
			var mesh:=split_mesh(source,node.skin,skeleton,arms)
			var path:=OUTPUT.path_join(entry[0]+("_arms.res" if arms else "_body.res"))
			if ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)!=OK:model.free();quit(1);return
			outputs[path]=FileAccess.get_sha256(path);counts[path]={"surfaces":mesh.get_surface_count(),"blend_shapes":mesh.get_blend_shape_count()}
	FileAccess.open(receipt,FileAccess.WRITE).store_string(JSON.stringify({"sources":sources,"outputs":outputs,"counts":counts},"  ")+"\n")
	print("FIRST_PERSON_MESHES baked ",JSON.stringify(counts));model.free();quit()
