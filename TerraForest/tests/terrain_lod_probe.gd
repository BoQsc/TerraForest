extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var rows: Array = []
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://inputs.json"))
	for name: String in inputs:
		var data := FileAccess.get_file_as_bytes("res://input/"+name+".bin")
		var nv := data.decode_u32(0)
		var packed := PackedByteArray()
		packed.resize(8)
		packed.encode_u32(0,TYPE_PACKED_VECTOR3_ARRAY)
		packed.encode_u32(4,nv)
		packed.append_array(data.slice(8,8+12*nv))
		var points: PackedVector3Array = bytes_to_var(packed)
		var indices := data.slice(8+12*nv).to_int32_array()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_INDEX] = indices
		var normal_begin := Time.get_ticks_usec()
		var source_mesh := ArrayMesh.new()
		source_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var normal_builder := SurfaceTool.new()
		normal_builder.create_from(source_mesh,0)
		normal_builder.generate_normals()
		arrays = normal_builder.commit_to_arrays()
		var normals_ms := (Time.get_ticks_usec()-normal_begin)/1000.0
		var mesh := ImporterMesh.new()
		mesh.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var begin := Time.get_ticks_usec()
		mesh.generate_lods(25.0,60.0,[])
		var elapsed := (Time.get_ticks_usec()-begin)/1000.0
		var after := mesh.get_surface_arrays(0)
		points = after[Mesh.ARRAY_VERTEX]
		var levels: Array = []
		for level in range(-1,mesh.get_surface_lod_count(0)):
			indices = after[Mesh.ARRAY_INDEX] if level==-1 else mesh.get_surface_lod_indices(0,level)
			var output := "%s_lod%d.bin" % [name,level]
			var file := FileAccess.open("res://output/"+output,FileAccess.WRITE)
			file.store_32(points.size())
			file.store_32(indices.size())
			file.store_buffer(points.to_byte_array())
			file.store_buffer(indices.to_byte_array())
			file.close()
			levels.append({"level":level,"file":output,"triangles":indices.size()/3,"engine_lod_size":0 if level==-1 else mesh.get_surface_lod_size(0,level)})
		rows.append({"name":name,"normals_ms":normals_ms,"generate_ms":elapsed,"levels":levels})
	var file := FileAccess.open("res://output/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info(),"rows":rows}))
	file.close()
	quit()
