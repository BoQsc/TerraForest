# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var damage: RefCounted=ClassDB.instantiate("NativeVehicleDamage")
	var original=load("res://vehicle_demo/scripts/car.gd").new()
	var scene=load("res://vehicle_demo/scenes/car.tscn").instantiate()
	scene.freeze=true;root.add_child(scene);scene.set_physics_process(false)
	var compared:=0;var max_error:=0.0;var passed:=true
	var native_us:=0;var script_us:=0
	for visual in scene._damage_visuals:
		var source: Mesh=visual.mesh
		var untouched: PackedVector3Array=source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var point: Vector3=visual.global_transform*untouched[0]
		var start:=Time.get_ticks_usec()
		var expected: ArrayMesh=original._build_dented_mesh(visual,point,Vector3(0.1,-0.2,0.7),1.0,0.15)
		script_us+=Time.get_ticks_usec()-start
		start=Time.get_ticks_usec()
		var actual: ArrayMesh=damage.dent(source,visual.global_transform,point,Vector3(0.1,-0.2,0.7),1.0,0.15)
		native_us+=Time.get_ticks_usec()-start
		passed=passed and actual!=null and expected!=null
		if actual==null or expected==null: continue
		for s in source.get_surface_count():
			var a: PackedVector3Array=actual.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var b: PackedVector3Array=expected.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for i in a.size(): max_error=maxf(max_error,a[i].distance_to(b[i]));compared+=1
			passed=passed and actual.surface_get_material(s)==source.surface_get_material(s)
		passed=passed and untouched==source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		passed=passed and damage.dent(source,visual.global_transform,point+Vector3(10000,0,0),Vector3.UP,1,0.1)==null
		passed=passed and damage.dent(source,visual.global_transform,point,Vector3.UP,0,0.1)==null
	passed=passed and compared>100 and max_error<0.00001
	print("DAMAGE_PARITY ",{"passed":passed,"vertices":compared,"max_error_m":max_error,"native_us":native_us,"script_us":script_us,"meshes":scene._damage_visuals.size()})
	original.free();scene.free();quit(0 if passed else 1)
