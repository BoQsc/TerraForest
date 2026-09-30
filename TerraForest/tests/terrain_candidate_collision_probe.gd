extends SceneTree
var checks: Array[Dictionary] = []
var failures := 0
var rays: Array[Dictionary] = []
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks.append({"passed":ok,"name":label})
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func run() -> void:
	var loaded := GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	check(loaded==OK or loaded==GDExtensionManager.LOAD_STATUS_ALREADY_LOADED,"native collision extension loads")
	if not ClassDB.class_exists("NativeTerrainCollision"):
		quit(1)
		return
	var recipes: RefCounted = ClassDB.instantiate("NativeTerrainCollision")
	var scene := Node3D.new()
	root.add_child(scene)
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures.json"))
	var regression: Array = []
	if FileAccess.file_exists("res://regression_rays.json"):
		regression=JSON.parse_string(FileAccess.get_file_as_string("res://regression_rays.json"))
	for fixture: String in fixtures:
		var values := FileAccess.get_file_as_bytes("res://faces/"+fixture).to_float32_array()
		var faces := PackedVector3Array()
		faces.resize(values.size()/3)
		for i in range(faces.size()): faces[i]=Vector3(values[3*i],values[3*i+1],values[3*i+2])
		var prepared: Dictionary = recipes.prepare(faces,1024)
		check(prepared.get("ok",false),fixture+" native recipe accepted")
		if not prepared.get("ok",false): continue
		var body := StaticBody3D.new()
		scene.add_child(body)
		var reconstructed := PackedVector3Array()
		for piece: RefCounted in prepared.pieces:
			reconstructed.append_array(piece.get_faces())
			var resolved: Dictionary = piece.resolve({})
			var collider := CollisionShape3D.new()
			collider.shape=resolved.shape
			body.add_child(collider)
		check(reconstructed==faces,fixture+" collision recipes preserve exact triangles")
		await physics_frame
		await process_frame
		await physics_frame
		await process_frame
		var hits := 0
		var attempted := 0
		var triangles: int = faces.size()/3
		for sample in range(12):
			var at: int = int((sample+0.5)*triangles/12.0)*3
			var a := faces[at]
			var b := faces[at+1]
			var c := faces[at+2]
			var normal := (b-a).cross(c-a).normalized()
			var center := (a+b+c)/3.0
			attempted += 1
			var query := PhysicsRayQueryParameters3D.create(center+normal*0.02,center-normal*0.02,1)
			query.hit_back_faces=true
			var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
			rays.append({"fixture":fixture,"triangle":at/3,"twice_area":(b-a).cross(c-a).length(),"a":[a.x,a.y,a.z],"b":[b.x,b.y,b.z],"c":[c.x,c.y,c.z],"hit":not hit.is_empty(),"distance":hit.position.distance_to(center) if not hit.is_empty() else -1.0})
			if not hit.is_empty() and hit.position.distance_to(center)<0.002: hits += 1
		check(attempted==12 and hits==12,fixture+" physics rays agree with 12 triangle centers (%d/12)" % hits)
		for old: Dictionary in regression:
			if old.fixture!=fixture: continue
			var a := Vector3(old.a[0],old.a[1],old.a[2])
			var b := Vector3(old.b[0],old.b[1],old.b[2])
			var c := Vector3(old.c[0],old.c[1],old.c[2])
			var center := (a+b+c)/3.0
			var normal := (b-a).cross(c-a).normalized()
			var query := PhysicsRayQueryParameters3D.create(center+normal*0.02,center-normal*0.02,1)
			query.hit_back_faces=true
			var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
			check(not hit.is_empty() and hit.position.distance_to(center)<0.002,fixture+" frozen failed ray %d" % old.triangle)
		body.free()
	scene.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/collision.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"checks":checks,"rays":rays,"scope":"Headless candidate fixture geometry through existing native collision recipes and real physics rays. No worker integration, rendered visuals, edit publication, collision cooking budget or FPS qualification."},"  "))
	file.close()
	quit(0 if failures==0 else 1)
