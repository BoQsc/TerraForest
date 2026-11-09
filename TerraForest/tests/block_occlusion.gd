# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var results:Array[Dictionary]=[]
func _initialize()->void:
	if not ClassDB.class_exists("NativeBlockWorld"):GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	results.append({"ok":ok,"label":label});print(("PASS " if ok else "FAIL ")+label)
func make_world()->Node3D:
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(blocks)
	blocks.set_collision_radius(0);return blocks
func nodes(blocks:Node3D)->Array[OccluderInstance3D]:
	var found:Array[OccluderInstance3D]=[]
	for mesh:Node in blocks.get_children():
		if mesh is MeshInstance3D:
			for child:Node in mesh.get_children():
				if child is OccluderInstance3D:found.append(child)
	return found
func ray_blocked(blocks:Node3D,from:Vector3,to:Vector3)->bool:
	for node:OccluderInstance3D in nodes(blocks):
		if not node.is_visible_in_tree():continue
		var shape:ArrayOccluder3D=node.occluder
		var vertices:=shape.vertices;var indices:=shape.indices
		var inverse:=node.global_transform.affine_inverse()
		for i:int in range(0,indices.size(),3):
			if Geometry3D.segment_intersects_triangle(inverse*from,inverse*to,vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]])!=null:return true
	return false
func exact(blocks:Node3D)->bool:
	for node:OccluderInstance3D in nodes(blocks):
		var mesh:MeshInstance3D=node.get_parent();var arrays:Array=mesh.mesh.surface_get_arrays(0)
		if node.occluder.vertices!=arrays[Mesh.ARRAY_VERTEX] or node.occluder.indices!=arrays[Mesh.ARRAY_INDEX] or node.global_transform!=mesh.global_transform:return false
	return true
func screenshot(label:String)->void:
	if not "--occlusion-images" in OS.get_cmdline_user_args():return
	for i:int in 8:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/block_occlusion_visual/"+label+".png")
func run()->void:
	var blocks:=make_world()
	if not blocks.has_method("configure_occlusion"):check(false,"native occlusion API installed");blocks.free();quit(1);return
	check(blocks.configure_occlusion(true,96,128,2097152),"bounded occlusion configuration accepted")
	check(not blocks.configure_occlusion(true,NAN,128,2097152) and not blocks.configure_occlusion(true,96,0,2097152) and not blocks.configure_occlusion(true,96,128,1),"invalid limits rejected")
	var cells:=PackedInt32Array()
	for y:int in 4:
		for x:int in 6:
			if x==2 and y in [1,2]:continue
			cells.append_array(PackedInt32Array([x,y,0,1]))
	check(blocks.set_cells(cells),"wall with authored doorway installed");blocks.flush_bakes()
	var original:PackedByteArray=blocks.capture_snapshot()
	check(blocks.occlusion_stats().active==1 and exact(blocks),"occluder reuses exact native mesh geometry and transform")
	check(not blocks.set_cells(PackedInt32Array([2,1,0,-1])) and blocks.occlusion_stats().active==1,"rejected edit preserves valid occlusion")
	check(not ray_blocked(blocks,Vector3(2.5,1.5,-2),Vector3(2.5,1.5,5)),"authored doorway has no occluding triangles")
	check(ray_blocked(blocks,Vector3(1.5,1.5,-2),Vector3(1.5,1.5,5)),"opaque wall blocks line of sight")
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(2.5,1.5,-7);camera.look_at(Vector3(2.5,1.5,0));camera.current=true
	var target:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.8,.8,.8);target.mesh=box
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color.MAGENTA;target.material_override=material
	root.add_child(target);target.position=Vector3(2.5,1.5,3)
	var sun:=DirectionalLight3D.new();root.add_child(sun);sun.rotation_degrees=Vector3(-30,150,0)
	root.use_occlusion_culling=true;DirAccess.make_dir_recursive_absolute("res://reports/block_occlusion_visual")
	await screenshot("open_on")
	root.use_occlusion_culling=false;await screenshot("open_off");root.use_occlusion_culling=true
	check(blocks.set_cells(PackedInt32Array([2,1,0,1,2,2,0,1])) and blocks.occlusion_stats().active==0,"edit hides old occluder before any bake")
	blocks.flush_bakes();check(ray_blocked(blocks,Vector3(2.5,1.5,-2),Vector3(2.5,1.5,5)),"closed doorway occludes after publication")
	await screenshot("closed_on")
	check(blocks.erase_cells(PackedInt32Array([2,1,0,1,2,2,0,1]),blocks.survey_revision_id()) and blocks.occlusion_stats().active==0,"destruction transaction disables stale walls immediately")
	check(not ray_blocked(blocks,Vector3(2.5,1.5,-2),Vector3(2.5,1.5,5)),"destroyed doorway cannot retain ghost occlusion")
	blocks.flush_bakes();check(blocks.capture_snapshot()==original and exact(blocks),"destruction restores exact cells and opening geometry")
	await screenshot("destroyed_on")
	var packet:PackedByteArray=blocks.capture_region(Vector3i.ZERO)
	check(blocks.unload_region(packet) and blocks.occlusion_stats().active==0,"region transfer invalidates occluder immediately")
	blocks.flush_bakes();check(nodes(blocks).is_empty() and blocks.occlusion_stats().geometry_bytes==0,"unloaded mesh releases all occluder nodes and geometry accounting")
	check(blocks.restore_region(packet,PackedByteArray()),"region reload accepts matching stored identity and empty current token")
	blocks.flush_bakes();check(exact(blocks) and blocks.occlusion_stats().active==1,"reload reconstructs exact occluder")
	blocks.position=Vector3(10,3,8);check(exact(blocks),"parent transform preserves mesh and occluder alignment");blocks.position=Vector3.ZERO
	var churn_ok:=true
	var steady_bytes:int=blocks.occlusion_stats().geometry_bytes
	for cycle:int in 40:
		churn_ok=blocks.set_cells(PackedInt32Array([2,1,0,1,2,2,0,1])) and churn_ok
		blocks.flush_bakes()
		churn_ok=blocks.erase_cells(PackedInt32Array([2,1,0,1,2,2,0,1]),blocks.survey_revision_id()) and churn_ok
		blocks.flush_bakes()
		churn_ok=churn_ok and nodes(blocks).size()==1 and blocks.occlusion_stats().geometry_bytes==steady_bytes and blocks.capture_snapshot()==original
		await process_frame
	check(churn_ok,"forty edit/destruction cycles preserve nodes bytes and authored data")
	check(blocks.configure_occlusion(false,96,128,2097152) and blocks.occlusion_stats().active==0,"disable hides all occluders synchronously")
	blocks.flush_bakes();check(nodes(blocks).is_empty() and blocks.capture_snapshot()==original,"disable retires nodes without modifying authored cells")
	blocks.free();camera.free();target.free();sun.free();root.use_occlusion_culling=false
	blocks=make_world();blocks.configure_occlusion(true,96,2,65536)
	cells.clear()
	for x:int in 8:cells.append_array(PackedInt32Array([x*16,0,0,1]))
	blocks.set_cells(cells);blocks.flush_bakes()
	check(blocks.occlusion_stats().resident==2 and blocks.occlusion_stats().geometry_bytes<=65536 and blocks.occlusion_stats().step_max_uploads==1,"count bytes and one-publication-per-step limits enforced")
	blocks.configure_streaming(true,16,1,65536,65536);blocks.set_focus(Vector3(120,8,8));blocks.flush_bakes()
	check(blocks.occlusion_stats().active==1 and nodes(blocks)[0].global_position.x==112,"travel evicts old occluders and selects the new resident chunk")
	blocks.configure_occlusion(true,16,2,65536);blocks.set_focus(Vector3(1000,0,0));blocks.flush_bakes()
	check(blocks.occlusion_stats().resident==0 and nodes(blocks).is_empty(),"far focus retires all obsolete occlusion")
	blocks.free()
	blocks=make_world();blocks.configure_occlusion(true,96,128,2097152);cells.clear()
	for z:int in 16:
		for y:int in 16:
			for x:int in 16:
				if (x+y+z)%2==0:cells.append_array(PackedInt32Array([x,y,z,1]))
	blocks.set_cells(cells);blocks.flush_bakes()
	check(blocks.stats().mesh_chunks==1 and blocks.occlusion_stats().active==0 and blocks.occlusion_stats().oversized_chunks_skipped==1,"dense chunk remains rendered when occluder exceeds its per-chunk cap")
	blocks.free();await process_frame;await process_frame
	FileAccess.open("res://reports/block_occlusion.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"results":results}))
	print("BLOCK_OCCLUSION_RESULT ",checks," checks; ",failures," failures");quit(1 if failures else 0)
