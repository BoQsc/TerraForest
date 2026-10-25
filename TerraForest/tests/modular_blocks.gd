extends SceneTree

const Catalog = preload("res://addons/structures/shape_catalog.gd")
var failures := 0
var checks := 0
var timings: Array[float] = []

func _initialize() -> void:
	run.call_deferred()

func check(accepted: bool, label: String) -> void:
	checks += 1
	if not accepted:
		failures += 1
	print("PASS " if accepted else "FAIL ", label)

func area(world: Node3D) -> float:
	var total := 0.0
	for child in world.get_children():
		if child is MeshInstance3D:
			var arrays: Array = child.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for offset in range(0, indices.size(), 3):
				total += (vertices[indices[offset+1]]-vertices[indices[offset]]).cross(vertices[indices[offset+2]]-vertices[indices[offset]]).length() * 0.5
	return total

func run() -> void:
	var blocks: Node3D = ClassDB.instantiate("NativeBlockWorld")
	root.add_child(blocks)
	blocks.set_process(false)
	var empty: PackedByteArray = blocks.capture_snapshot()
	for shape_id in range(1, 9):
		for rotation in 4:
			for material in 4:
				var expected: int = (128 if shape_id==8 else shape_id) + rotation*8 + material*32
				check(blocks.encode_block(shape_id, rotation, material)==expected, "legacy word unchanged %d/%d/%d" % [shape_id,rotation,material])
	check(Catalog.NAMES.size()==18 and blocks.encode_block(19,0,0)==-1 and blocks.encode_block(9,24,0)==-1 and blocks.encode_block(8,4,0)==-1, "catalogue bounds reject unsupported shapes and rotations")
	var bases: Array[Basis] = []
	for rotation in 24:
		var orientation: Basis = blocks.shape_orientation(rotation)
		check(is_equal_approx(orientation.determinant(),1.0) and not orientation in bases, "unique proper grid rotation %d" % rotation)
		bases.append(orientation)
	var fixtures: Array = [
		[Vector3(.5,.06,.5),Vector3(.5,.5,.5)],
		[Vector3(.06,.5,.5),Vector3(.5,.5,.5)],
		[Vector3(.66,.66,.5),Vector3(.3,.3,.5)],
		[Vector3(.5,.25,.5),Vector3(.05,.4,.5)],
		[Vector3(.8,.6,.8),Vector3(.2,.5,.8)],
		[Vector3(.8,.6,.2),Vector3(.2,.5,.2)],
		[Vector3(.5,.45,.5),Vector3(.5,.3,.5)],
		[Vector3(.04,.96,.5),Vector3(.4,.96,.5)],
		[Vector3(.5,.44,.5),Vector3(.5,.2,.5)],
		[Vector3(.04,.96,.5),Vector3(.5,.96,.5)]]
	var records := PackedInt32Array()
	var physics_probes: Array[Dictionary] = []
	for shape_id in range(9,19):
		for rotation in 24:
			var material: int = rotation%4
			var word: int = blocks.encode_block(shape_id,rotation,material)
			check(blocks.decode_block(word)=={"shape":shape_id,"rotation":rotation,"material":material}, "extended word roundtrip %d/%d" % [shape_id,rotation])
			check(blocks.set_cells(PackedInt32Array([0,0,0,word])), "native cell accepts modular shape")
			var center := Vector3.ONE*.5
			var solid: Vector3 = bases[rotation]*(fixtures[shape_id-9][0]-center)+center
			var hole: Vector3 = bases[rotation]*(fixtures[shape_id-9][1]-center)+center
			check(blocks.sample_solid(PackedVector3Array([solid,hole]))==PackedByteArray([1,0]), "real solid and empty volume %d/%d" % [shape_id,rotation])
			var hulls: Dictionary = blocks.solid_hulls(AABB(Vector3.ZERO,Vector3.ONE))
			check(hulls.ok and not hulls.hulls.is_empty(), "native water/solid hulls available")
			var mesh: Mesh = blocks.preview_mesh(shape_id,rotation)
			var arrays: Array = mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var correct := true
			for vertex in vertices:
				correct = correct and vertex.x>=-.000001 and vertex.y>=-.000001 and vertex.z>=-.000001 and vertex.x<=1.000001 and vertex.y<=1.000001 and vertex.z<=1.000001
			for offset in range(0,indices.size(),3):
				var cross := (vertices[indices[offset+1]]-vertices[indices[offset]]).cross(vertices[indices[offset+2]]-vertices[indices[offset]])
				correct = correct and cross.dot(normals[indices[offset]]) < -0.000001
			check(correct and blocks.preview_mesh(shape_id,rotation)==mesh, "grid-bounded cached preview and outward normals")
			var surface_points:=PackedVector3Array()
			for offset in range(0,indices.size(),3):
				var first:=vertices[indices[offset]];var second:=vertices[indices[offset+1]];var third:=vertices[indices[offset+2]]
				var outward:=(third-first).cross(second-first).normalized()
				var middle:=(first+second+third)/3.0
				surface_points.append(middle-outward*.0001);surface_points.append(middle+outward*.0001)
			var occupied:PackedByteArray=blocks.sample_solid(surface_points)
			var matched:=true
			for sample in occupied.size():matched=matched and occupied[sample]==(1 if sample%2==0 else 0)
			check(matched,"every render triangle separates exact solid and empty space")
			var origin := Vector3i((shape_id-9)*3,0,rotation*3)
			records.append_array(PackedInt32Array([origin.x,origin.y,origin.z,word]))
			var direction: Vector3 = bases[rotation]*Vector3.BACK
			physics_probes.append({"from":Vector3(origin)+solid+direction*2,"to":Vector3(origin)+solid-direction*2,"cell":origin})
	check(blocks.restore_snapshot(empty) and blocks.set_cells(records), "240 rotated independently stored blocks")
	blocks.set_collision_radius(256)
	blocks.flush_bakes()
	for frame in 4:
		await physics_frame
		await process_frame
	for probe in physics_probes:
		var authored: Dictionary = blocks.raycast_cells(probe.from,probe.to)
		var physics: Dictionary = root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(probe.from,probe.to,2))
		check(authored.get("cell")==probe.cell and not physics.is_empty() and authored.position.distance_to(physics.position)<.002, "physical collider matches exact authored surface %s" % probe.cell)
	var saved: PackedByteArray = blocks.capture_snapshot()
	check(saved.decode_u32(4)==2 and blocks.restore_snapshot(saved) and blocks.capture_snapshot()==saved, "version-two binary snapshot exact roundtrip")
	for invalid in [256,32792,32896,35328,65536,-1]:
		check(not blocks.set_cells(PackedInt32Array([1,1,1,invalid])) and blocks.capture_snapshot()==saved, "invalid extended word is atomic %d" % invalid)
	var packet: PackedByteArray = blocks.capture_region(Vector3i.ZERO)
	check(blocks.validate_region_snapshot(packet) and blocks.unload_region(packet) and blocks.restore_region(packet,PackedByteArray()), "binary region paging preserves modular words")
	check(blocks.capture_snapshot()==saved, "paging roundtrip preserves all block identities")
	var prefab: Resource = ClassDB.instantiate("NativeBlockPrefab")
	for orientation in 24:
		var word: int = blocks.encode_block(11,orientation,2)
		check(prefab.configure(PackedInt32Array([0,0,0,word])), "modular prefab configured")
		for turn in 4:
			blocks.restore_snapshot(empty)
			check(blocks.place_prefab(prefab,Vector3i.ZERO,turn) and blocks.get_cell(Vector3i.ZERO)==blocks.encode_block(11,(orientation/4)*4+(orientation+turn)%4,2), "prefab yaw preserves mount %d/%d" % [orientation,turn])
	blocks.restore_snapshot(empty)
	check(blocks.configure_history(1024*1024,32), "native history enabled")
	var panel: int = blocks.encode_block(9,0,0)
	for origin in [0,15,-1]:
		for neighbor in [panel,1]:
			blocks.restore_snapshot(empty)
			blocks.set_cells(PackedInt32Array([origin,0,0,panel,origin+1,0,0,neighbor]))
			blocks.flush_bakes()
			var expected := 4.75 if neighbor==panel else 8.25
			check(absf(area(blocks)-expected)<.0001, "partial faces culled both directions across seam %d/%d" % [origin,neighbor])
	blocks.restore_snapshot(empty)
	var left: int = blocks.encode_block(11,2,2)
	var right: int = blocks.encode_block(11,0,2)
	blocks.set_cells(PackedInt32Array([0,0,0,left,1,0,0,right]))
	blocks.flush_bakes()
	var assembly: PackedByteArray = blocks.capture_snapshot()
	var arch_area:=area(blocks)
	blocks.set_cells(PackedInt32Array([1,0,0,0]));blocks.flush_bakes()
	check(absf(arch_area-(area(blocks)*2.0-.25))<.0001,"arch halves remove only their shared cap, retaining the opening")
	blocks.restore_snapshot(assembly)
	blocks.set_cells(PackedInt32Array([0,-1,0,blocks.encode_block(9,20,2),1,-1,0,blocks.encode_block(9,16,2)]))
	blocks.flush_bakes()
	for frame in 4:
		await physics_frame
		await process_frame
	var capsule:=CapsuleShape3D.new();capsule.radius=.35;capsule.height=1.8
	var clearance:=PhysicsShapeQueryParameters3D.new();clearance.shape=capsule;clearance.transform=Transform3D(Basis.IDENTITY,Vector3(1,-.1,.5));clearance.collision_mask=2
	check(root.world_3d.direct_space_state.intersect_shape(clearance,1).is_empty(),"four-block archway clears a 1.8-metre player capsule")
	blocks.restore_snapshot(assembly)
	blocks.set_cells(PackedInt32Array([0,0,0,left]))
	check(blocks.set_cells(PackedInt32Array([0,0,0,0])) and blocks.get_cell(Vector3i.RIGHT)==right, "removing one arch block preserves the other")
	check(blocks.undo() and blocks.capture_snapshot()==assembly and blocks.redo() and blocks.get_cell(Vector3i.ZERO)==0, "independent removal has exact undo and redo")
	blocks.restore_snapshot(empty)
	var legacy := PackedInt32Array([0,0,0,1,16,0,0,192])
	blocks.set_cells(legacy)
	check(blocks.capture_snapshot().decode_u32(4)==1, "legacy-only worlds retain version-one storage")
	blocks.restore_snapshot(empty)
	var mixed := PackedInt32Array()
	for row in 8:
		for column in 8:
			mixed.append_array(PackedInt32Array([column*2,0,row*2,blocks.encode_block(9+(row+column)%6,(row*8+column)%24,(row+column)%4)]))
	blocks.set_cells(mixed)
	blocks.flush_bakes()
	for repeat in 8:
		var started := Time.get_ticks_usec()
		blocks.set_cells(PackedInt32Array([0,0,0,0 if repeat%2==0 else panel]))
		blocks.flush_bakes()
		timings.append((Time.get_ticks_usec()-started)/1000.0)
	check(blocks.stats().worker_threads_started==1, "mixed shapes use the existing bounded native worker")
	var palette := preload("res://addons/structures/construction_palette.gd").new()
	root.add_child(palette)
	palette.synchronize(true,11,2,23,-1)
	check(palette.shape.item_count==18 and palette.rotation_choice.item_count==24 and palette.rotation_choice.selected==23, "ALT palette exposes new shapes and all 24 orientations")
	palette.synchronize(true,1,0,0,-1)
	check(palette.rotation_choice.item_count==4, "legacy blocks retain their four rotations")
	palette.free()
	blocks.free()
	DirAccess.make_dir_recursive_absolute("res://reports/modular_blocks")
	FileAccess.open("res://reports/modular_blocks/component.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"edit_flush_ms":timings,"scope":"64 mixed modular cells; synchronous explicit flush includes worker wait and collision; not frame-time"},"  "))
	print("MODULAR_BLOCKS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
