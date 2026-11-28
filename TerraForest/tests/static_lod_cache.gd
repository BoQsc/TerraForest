# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("CHECK ","PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func settle()->void:
	for frame in 12:await RenderingServer.frame_post_draw
func read_rows(batch:Node)->Dictionary:
	var result:Dictionary={}
	for page in batch.get_children():
		if not page is MultiMeshInstance3D or not page.visible:continue
		# Full-buffer readback does not prime the engine's per-instance cache.
		var data:PackedFloat32Array=page.multimesh.buffer
		for index in page.multimesh.instance_count:
			var row:=data.slice(index*16,(index+1)*16)
			result[roundi(row[3]+page.position.x)]=row
	return result
func run()->void:
	if DisplayServer.get_name()=="headless":push_error("Rendered buffer verification required");quit(1);return
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true;camera.position=Vector3(2,2,5)
	var prototype:=BoxMesh.new();var arrays:=prototype.get_mesh_arrays()
	var full:=ArrayMesh.new();var near:=ArrayMesh.new();var far:=ArrayMesh.new()
	for mesh:ArrayMesh in [full,near,far]:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.custom_aabb=prototype.get_aabb()
	full.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
	check(batch.configure_asset("cache/fixture",full) and batch.configure_appearance_fade() and batch.configure_render_streaming(true,96,8,4096,2,1024),"bounded native fade batch")
	check(batch.configure_surface_lod(near,far,.03),"native surface LOD enabled before allocation")
	batch.set_casts_shadows(false);batch.set_render_focus(Vector3(2,0,0))
	var poses:Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(1,0,0)),Transform3D(Basis.IDENTITY,Vector3(2,0,0))]
	check(batch.upsert_transforms(PackedInt64Array([1,2]),poses),"initial authoritative transforms")
	await settle();var first:=read_rows(batch);var saved:PackedByteArray=batch.capture_snapshot()
	check(first.size()==2 and first[1][0]==1.0 and first[1][5]==1.0 and first[1][10]==1.0 and first[1][3]==1.0 and first[2][3]==2.0 and first[1][13]==1.0,"cache initialization is overwritten by exact pose and appearance data")
	var modes:Dictionary={}
	for distance in [5.0,200.0,5.0,200.0,5.0]:
		camera.position=Vector3(2,2,distance);batch.update_surface_lod();await settle()
		for page in batch.get_children():
			if page is MultiMeshInstance3D and page.visible:modes[page.multimesh.mesh.get_instance_id()]=true
		check(read_rows(batch)==first and batch.capture_snapshot()==saved,"mesh switch preserves GPU bytes and authoritative snapshot")
	check(modes.size()>=2,"camera actually exercises multiple surface meshes")
	check(batch.upsert_transforms(PackedInt64Array([3]),[Transform3D(Basis.IDENTITY,Vector3(3,0,0))]),"grow native page")
	await settle();var grown:=read_rows(batch)
	check(grown.size()==3 and grown[1]==first[1] and grown[2]==first[2] and grown[3][3]==3.0,"reallocation preserves old buffers and initializes new identity")
	check(batch.remove_instances(PackedInt64Array([3])),"shrink native page")
	await settle();check(read_rows(batch)==first and batch.capture_snapshot()==saved,"count reduction preserves remaining bytes")
	batch.set_render_focus(Vector3(1000,0,1000));await settle()
	batch.set_render_focus(Vector3(2,0,0));await settle()
	check(read_rows(batch)==first and batch.capture_snapshot()==saved,"pool reuse restores exact transforms and stable appearance births")
	batch.free()
	for path in ["res://tests/static_lod_cache.gd","res://tests/walking_performance.gd"]:
		if not FileAccess.file_exists(path+".uid"):FileAccess.open(path+".uid",FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	print("STATIC_LOD_CACHE failures=",failures);quit(0 if failures==0 else 1)
