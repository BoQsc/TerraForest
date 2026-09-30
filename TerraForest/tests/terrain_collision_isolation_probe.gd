extends SceneTree
var results: Array[Dictionary] = []
var sweeps: Array[Dictionary] = []
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var recipes: RefCounted = ClassDB.instantiate("NativeTerrainCollision")
	var scene := Node3D.new()
	root.add_child(scene)
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://input.json"))
	for row: Dictionary in fixtures:
		var a := Vector3(row.a[0],row.a[1],row.a[2])
		var b := Vector3(row.b[0],row.b[1],row.b[2])
		var c := Vector3(row.c[0],row.c[1],row.c[2])
		for mode in ["world_vertices","local_vertices_world_body","origin"]:
			for scale_factor in [1.0,4.0,16.0,64.0]:
				var offset := a if mode=="world_vertices" else Vector3.ZERO
				var faces := PackedVector3Array([offset,offset+(b-a)*scale_factor,offset+(c-a)*scale_factor])
				var prepared: Dictionary = recipes.prepare(faces,1024)
				assert(prepared.ok)
				var resolved: Dictionary = prepared.pieces[0].resolve({})
				assert(resolved.ok)
				var body := StaticBody3D.new()
				if mode=="local_vertices_world_body": body.position=a
				var collider := CollisionShape3D.new()
				collider.shape=resolved.shape
				body.add_child(collider)
				scene.add_child(body)
				await physics_frame
				await process_frame
				await physics_frame
				await process_frame
				var center := (faces[0]+faces[1]+faces[2])/3.0+body.position
				var normal := (faces[1]-faces[0]).cross(faces[2]-faces[0]).normalized()
				var tangent := (faces[1]-faces[0]).normalized()
				for kind in ["sphere","capsule"]:
					var shape: Shape3D
					if kind=="sphere":
						var sphere := SphereShape3D.new()
						sphere.radius=0.25
						shape=sphere
					else:
						var capsule := CapsuleShape3D.new()
						capsule.radius=0.25
						capsule.height=1.5
						shape=capsule
					for displaced in [false,true]:
						var query := PhysicsShapeQueryParameters3D.new()
						query.shape=shape
						query.margin=0.0
						query.collision_mask=1
						query.transform=Transform3D(Basis.IDENTITY,center+normal*2.0+(tangent*10.0 if displaced else Vector3.ZERO))
						query.motion=-normal*4.0
						var fractions := scene.get_world_3d().direct_space_state.cast_motion(query)
						sweeps.append({"fixture":row.fixture,"triangle":row.triangle,"mode":mode,"scale":scale_factor,"shape":kind,"displaced_control":displaced,"safe_fraction":fractions[0],"unsafe_fraction":fractions[1],"hit":fractions[0]<1.0})
				for reach: float in [0.02,2.0,20.0]:
					var start := center+normal*reach
					var finish := center-normal*reach
					var query := PhysicsRayQueryParameters3D.create(start,finish,1)
					query.hit_back_faces=true
					var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
					var analytic: Variant = Geometry3D.ray_intersects_triangle(start,finish-start,faces[0]+body.position,faces[1]+body.position,faces[2]+body.position)
					results.append({"fixture":row.fixture,"triangle":row.triangle,"mode":mode,"scale":scale_factor,"ray_half_length":reach,"twice_area":(faces[1]-faces[0]).cross(faces[2]-faces[0]).length(),"physics_hit":not hit.is_empty(),"distance":hit.position.distance_to(center) if not hit.is_empty() else -1.0,"geometry_ray_hit":analytic!=null,"geometry_unit_ray_hit":Geometry3D.ray_intersects_triangle(start,-normal,faces[0]+body.position,faces[1]+body.position,faces[2]+body.position)!=null})
				body.free()
	scene.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/isolation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"results":results,"sweeps":sweeps,"scope":"Single-triangle ray and sphere/capsule sweep diagnosis using frozen missed-ray faces; scaling is diagnostic, not a proposed geometry modification. Sweeps do not qualify dynamic body stability."},"  "))
	file.close()
	print("Completed ",results.size()," isolated triangle cases")
	quit()
