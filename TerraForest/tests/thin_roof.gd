extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:run.call_deferred()

func check(accepted: bool, label: String) -> void:
	checks+=1
	if not accepted:failures+=1
	print("PASS " if accepted else "FAIL ",label)

func area(blocks: Node3D) -> float:
	var result:=0.0
	for child in blocks.get_children():
		if not child is MeshInstance3D:continue
		var arrays: Array=child.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for offset in range(0,indices.size(),3):
			result+=(vertices[indices[offset+1]]-vertices[indices[offset]]).cross(vertices[indices[offset+2]]-vertices[indices[offset]]).length()*.5
	return result

func run() -> void:
	var blocks: Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(blocks)
	blocks.set_process(false);blocks.set_collision_radius(256)
	check(blocks.configure_history(1024*1024,32),"independent native roof-cell history enabled")
	for origin: Vector3i in [Vector3i(14,0,-1),Vector3i(-17,0,15)]:
		var records:=PackedInt32Array()
		for column in range(-4,5):
			for row in 2:
				var cell:=origin+Vector3i(column,4-absi(column),row)
				var rotation:=0 if column<=0 else 2
				records.append_array(PackedInt32Array([cell.x,cell.y,cell.z,blocks.encode_block(17 if column==0 else 15,rotation,1)]))
				records.append_array(PackedInt32Array([cell.x,cell.y-1,cell.z,blocks.encode_block(18 if column==0 else 16,rotation,1)]))
		check(blocks.set_cells(records),"36 individually keyed shell/seam cells publish "+str(origin))
		blocks.set_focus(Vector3(origin));blocks.flush_bakes()
		for frame in 4:await physics_frame
		var points:=PackedVector3Array()
		var continuous:=true
		var physical:=true
		for step in range(1,360):
			var across: float=-4+float(step)/40
			var top: float=4+minf(across,1-across)
			for depth in [.01,.99,1.01,1.99]:
				for vertical in [-.06,.01,-.16]:points.append(Vector3(origin)+Vector3(across,top+vertical,depth))
			if step%10!=0:continue
			for upward in [false,true]:
				var start:=Vector3(origin)+Vector3(across,top+(-1 if upward else 1),.5)
				var finish:=Vector3(origin)+Vector3(across,top+(1 if upward else -1),.5)
				var expected: float=origin.y+top-(.125 if upward else 0)
				var authored: Dictionary=blocks.raycast_cells(start,finish)
				var collider: Dictionary=root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,finish,2))
				physical=physical and not authored.is_empty() and not collider.is_empty()
				if not authored.is_empty() and not collider.is_empty():physical=physical and absf(authored.position.y-expected)<.001 and absf(collider.position.y-expected)<.001
		var solid: PackedByteArray=blocks.sample_solid(points)
		for index in solid.size():continuous=continuous and solid[index]==(1 if index%3==0 else 0)
		check(continuous,"continuous top and underside across slope, ridge and negative/positive chunk seams")
		check(physical,"physical and authoritative roof rays match both skin surfaces")
		var actual_area:=area(blocks)
		check(absf(actual_area-(36*sqrt(2.0)+2.75))<.001,"all covered phase/cell caps culled, exact thin-shell exterior area")
		if absf(actual_area-(36*sqrt(2.0)+2.75))>=.001:print("ROOF_AREA actual=",actual_area)
		var stored: PackedByteArray=blocks.capture_snapshot()
		var removed:=origin+Vector3i(-2,2,0)
		var neighbor:=removed+Vector3i(1,1,0)
		var neighbor_word: int=blocks.get_cell(neighbor)
		check(blocks.set_cells(PackedInt32Array([removed.x,removed.y,removed.z,0])) and blocks.get_cell(neighbor)==neighbor_word,"one roof block removal preserves its neighboring slope")
		check(blocks.raycast_cells(Vector3(removed)+Vector3(.5,2,.5),Vector3(removed)+Vector3(.5,-1,.5)).is_empty(),"removing one cell makes a real opening, not an intact cosmetic roof")
		check(blocks.undo() and blocks.capture_snapshot()==stored,"undo restores exact roof bytes")
		check(blocks.redo() and blocks.restore_snapshot(stored) and blocks.capture_snapshot()==stored,"redo and binary restore preserve all roof identities")
		for offset in range(0,records.size(),4):records[offset+3]=0
		check(blocks.set_cells(records),"clear isolated fixture before next chunk seam")
	blocks.free();await process_frame
	print("THIN_ROOF checks=",checks," failures=",failures)
	quit(1 if failures else 0)
