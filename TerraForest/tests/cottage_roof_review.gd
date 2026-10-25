extends "res://tests/modular_building_review.gd"

const Roof = preload("res://reviews/modular_buildings/roof_recipe.gd")

func run() -> void:
	output="res://reports/cottage_roof_review"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):output=argument.trim_prefix("--review-output=")
	DirAccess.make_dir_recursive_absolute(output)
	if "--bake-roof" in OS.get_cmdline_user_args():
		var authoring: Node3D=ClassDB.instantiate("NativeBlockWorld")
		var asset: Resource=Roof.build(authoring)
		check(asset!=null and ResourceSaver.save(asset,Roof.PATH)==OK,"bake review-only A2 roof prefab")
		authoring.free()
	viewer=load("res://reviews/modular_buildings/roof_viewer.gd").new();root.add_child(viewer)
	check(viewer.ready_ok,"A0 and A2 native buildings and signs load")
	if not viewer.ready_ok:viewer.free();quit(1);return
	var blocks: Node3D=viewer.structures.blocks
	if "--restore-review" in OS.get_cmdline_user_args():
		var stored:=FileAccess.get_file_as_bytes(output.path_join("roof.tfbs"))
		viewer.toggle_block()
		check(viewer.structures.restore_storage_snapshot(stored),"fresh process restores the comparison after roof removal")
		check(viewer.structures.capture_storage_snapshot()==stored,"fresh process reproduces exact roof and attachment bytes")
		viewer.free();await process_frame
		print("COTTAGE_ROOF_RESTORE checks=",checks," failures=",failures);quit(1 if failures else 0);return
	var design: Dictionary=viewer.designs[0]
	var original:=Recipes.cells_of(design.original)
	var candidate:=Recipes.cells_of(design.candidate)
	var retained:=true
	for cell: Vector3i in original:
		if cell.y<6 and candidate.get(cell)!=original[cell]:retained=false
	for cell: Vector3i in candidate:
		if cell.y<6 and not original.has(cell):
			retained=retained and cell.y==5 and absi(cell.x)==4 and absi(cell.z)==6 and blocks.decode_block(candidate[cell]).shape==16
	check(retained,"existing walls and stairs unchanged; only thin roof-edge seam cells added below eaves, no A1 porch")
	check(design.candidate.get_model_attachments()==design.original.get_model_attachments(),"doors, windows, furniture and storage remain exact originals")
	check(design.candidate.get_meta("review_only",false) and design.candidate.get_meta("review_revision")==2 and viewer.candidate_label.text=="PROPOSAL / NOT APPROVED","A2 is a separately identified unapproved revision")
	check(Roof.build(blocks).get_records()==design.candidate.get_records(),"baked A2 matches reproducible offline recipe")
	for shape_id in range(15,19):
		var found:=false
		for word in candidate.values():found=found or blocks.decode_block(word).shape==shape_id
		check(found,"roof uses independent native phase shape "+str(shape_id))
	for view_index in 3:
		viewer.select_view(0,view_index)
		await picture(["exterior","interior","edge_detail"][view_index])
	var stored: PackedByteArray=viewer.structures.capture_storage_snapshot()
	FileAccess.open(output.path_join("roof.tfbs"),FileAccess.WRITE).store_buffer(stored)
	viewer.select_view(0,2)
	var before: int=blocks.stats().cells
	press("Remove ONE roof block")
	check(viewer.removed and blocks.stats().cells==before-1,"review button removes exactly one roof grid block")
	blocks.flush_bakes();await picture("one_block_removed")
	var cell: Vector3i=design.remove
	check(blocks.get_cell(cell)==original[cell] and blocks.get_cell(cell+Vector3i(viewer.PAIR_OFFSET,0,0))==0,"original roof untouched while candidate has an actual hole")
	press("Restore that block")
	check(viewer.structures.capture_storage_snapshot()==stored,"restoring that block preserves exact compound bytes")
	press("Open / close doors")
	for frame in 8:await physics_frame
	await walk_designs()
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cells":design.candidate.get_cell_count(),"scope":"A2 roof-only review, no production building replacement or world migration"},"  "))
	viewer.free();await process_frame
	print("COTTAGE_ROOF_REVIEW checks=",checks," failures=",failures)
	quit(1 if failures else 0)
