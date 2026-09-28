extends SceneTree
var checks := 0
var failures := 0
var evidence := {}

func _initialize() -> void:
	if not ClassDB.class_exists("NativeBlockWorld"):
		GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1
	print(("PASS " if value else "FAIL ")+label)

func mesh_digest(world: Node3D) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	for child in world.get_children():
		if child is MeshInstance3D:
			hash.update(var_to_bytes(child.position))
			hash.update(var_to_bytes(child.mesh.surface_get_arrays(0)))
	return hash.finish().hex_encode()

func fixture(kind: int) -> PackedInt32Array:
	var records := PackedInt32Array()
	for z in range(16):
		for y in range(16):
			for x in range(16):
				var wall := x==0 or x==15 or z==0 or z==15 or y==0 or y==15
				if kind==0 and not wall: continue
				if kind==1 and (x+y+z)%3!=0: continue
				var shape := 1
				if kind==2: shape=2
				if kind==3: shape=3 if (x+y+z)%3==0 else 1
				if kind==4: shape=5 if (x+y+z)%3==0 else 2
				if kind==5:
					if (x+y+z)%7!=0: continue
					shape=4 if x%2==0 else 6
				records.append_array(PackedInt32Array([x,y,z,shape+((x+z)%4)*8+((x+y+z)%4)*32]))
	# Halo-dependent faces on both negative and positive chunk boundaries.
	for x in [-1,16]:
		for z in range(16):
			records.append_array(PackedInt32Array([x,0,z,2 if kind==2 else 1]))
	if kind==6: records.append_array(PackedInt32Array([16,1,3,3]))
	return records

func run() -> void:
	var baseline := {}
	var reference_path := "res://tests/fixtures/block_lattice_reference.json"
	if FileAccess.file_exists(reference_path): baseline=JSON.parse_string(FileAccess.get_file_as_string(reference_path))
	check(baseline.size()==7,"all seven legacy reference fixtures are available")
	for kind in range(7):
		var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
		root.add_child(world)
		world.set_collision_radius(0)
		var records := fixture(kind)
		check(world.set_cells(records),"fixture %d accepted" % kind)
		world.flush_bakes()
		var fingerprint := mesh_digest(world)
		var elapsed: Array[float] = []
		# Force a real rebake on a warm instance; exact output returns to the fixture.
		for repeat in range(8):
			world.set_cells(PackedInt32Array([0,0,0,0]))
			world.flush_bakes()
			var start := Time.get_ticks_usec()
			world.set_cells(records)
			world.flush_bakes()
			elapsed.append(float(Time.get_ticks_usec()-start)/1000.0)
		check(mesh_digest(world)==fingerprint,"fixture %d deterministic output" % kind)
		var stats: Dictionary = world.stats()
		var expected := [3,0,0]
		if kind==2: expected=[0,3,0]
		if kind==3 or kind==4: expected=[0,0,3]
		if kind==6: expected=[1,0,2]
		check([stats.get("bake_lattice_16_chunks",-1),stats.get("bake_lattice_32_chunks",-1),stats.get("bake_lattice_64_chunks",-1)]==expected,"fixture %d selects exact resolution including neighboring shapes" % kind)
		if baseline.has(str(kind)):
			check(fingerprint==baseline[str(kind)].sha256,"fixture %d exact legacy geometry/normals/UV/material/index bytes" % kind)
		elapsed.sort()
		evidence[str(kind)]={"sha256":fingerprint,"triangles":world.stats().triangles,"median_ms":elapsed[4],"max_ms":elapsed.back(),"stats":world.stats()}
		if kind==0:
			var saved: PackedByteArray = world.capture_snapshot()
			world.set_cells(PackedInt32Array([16,1,3,3]))
			world.flush_bakes()
			check(world.stats().bake_lattice_64_chunks==2,"neighbor stair edit promotes its own and dependent cube lattice")
			world.restore_snapshot(saved)
			world.flush_bakes()
			check(world.stats().bake_lattice_16_chunks==3 and mesh_digest(world)==fingerprint,"restoration removes obsolete fine detail and reproduces original surfaces")
		world.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/block_lattice.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"fixtures":evidence},"  "))
	file.close()
	print("BLOCK_LATTICE_RESULT ",JSON.stringify(evidence))
	quit(1 if failures else 0)
