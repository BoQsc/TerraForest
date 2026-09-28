extends SceneTree
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1
	print(("PASS " if value else "FAIL ")+label)

func _initialize() -> void:
	if not ClassDB.class_exists("NativeBlockWorld"):
		GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()

func run() -> void:
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	root.add_child(world)
	var occupied := AABB(Vector3(-1,0,0),Vector3.ONE)
	check(world.is_collision_region_ready(occupied),"empty region does not block movement")
	check(not world.is_collision_region_ready(AABB()) and not world.is_collision_region_ready(AABB(Vector3(NAN,0,0),Vector3.ONE)),"invalid readiness volumes fail closed")
	world.set_cells(PackedInt32Array([-1,0,0,1,16,0,0,1]))
	world.set_process(false)
	check(not world.is_collision_region_ready(occupied),"unbaked negative-coordinate cell blocks entry")
	check(world.is_collision_region_ready(AABB(Vector3(-1,2,0),Vector3.ONE)),"empty space within the same unfinished chunk remains traversable")
	check(world.is_collision_region_ready(AABB(Vector3(0,0,0),Vector3.ONE)),"face-touching volume does not falsely overlap adjacent occupied cell")
	world.set_collision_radius(0);world.flush_bakes()
	check(not world.is_collision_region_ready(occupied),"render-ready cell with disabled collision blocks entry")
	world.set_collision_radius(48);world.flush_bakes()
	check(world.is_collision_region_ready(occupied),"completed collision releases the movement gate")
	world.set_cells(PackedInt32Array([-1,0,0,2]))
	check(not world.is_collision_region_ready(occupied),"edit invalidates readiness before old physics is replaced")
	world.flush_bakes()
	check(world.is_collision_region_ready(occupied),"edited collision restores readiness")
	world.set_focus(Vector3(1000,1000,1000));world.flush_bakes()
	check(not world.is_collision_region_ready(occupied),"out-of-range authored surface is not treated as ready")
	world.set_focus(Vector3.ZERO);world.flush_bakes()
	world.position=Vector3(100,20,-30)
	world.rotation_degrees.y=90
	var transformed: AABB = world.global_transform*occupied
	check(world.is_collision_region_ready(transformed),"world-space bounds respect translated and rotated block worlds")
	world.set_cells(PackedInt32Array([-1,0,0,1]))
	check(not world.is_collision_region_ready(transformed),"transformed dirty surface still blocks entry")
	world.flush_bakes()
	world.scale=Vector3.ZERO
	check(not world.is_collision_region_ready(transformed),"singular transforms fail closed")
	world.scale=Vector3.ONE
	world.position=Vector3.ZERO;world.rotation=Vector3.ZERO
	world.configure_streaming(true,16,1,65536,0)
	world.set_focus(Vector3(-8,8,8));world.flush_bakes()
	check(not world.is_collision_region_ready(AABB(Vector3(16,0,0),Vector3.ONE)),"chunk-limit deferred surface blocks entry even when other chunks are ready")
	world.set_cells(PackedInt32Array([16,0,0,0]))
	check(world.is_collision_region_ready(AABB(Vector3(16,0,0),Vector3.ONE)),"deleted deferred surface no longer blocks empty space")
	world.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/building_readiness.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	file.close()
	quit(1 if failures else 0)
