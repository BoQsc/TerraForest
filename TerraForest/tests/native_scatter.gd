# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	var native=ClassDB.instantiate("NativeVegetationScatter")
	var reference: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/scatter_reference.json"))
	var failures:=0
	var ecosystem=load("res://addons/world_ecosystem/world_ecosystem.gd").new()
	for row: Dictionary in reference:
		ecosystem.seed=int(row.seed);ecosystem.density=row.density
		var integrated: Dictionary=ecosystem._candidates(Vector2i(int(row.x),int(row.z)))
		var actual: Dictionary=native.candidates(Vector2i(int(row.x),int(row.z)),int(row.seed),row.density)
		for field in ["points","ids","rotations","scales"]:
			if integrated[field].to_byte_array().hex_encode()!=row[field]: failures+=1;print("FAIL integrated bytes ",field)
			if actual[field].to_byte_array().hex_encode()!=row[field]:
				failures+=1;print("FAIL legacy bytes ",row.seed," ",row.x," ",row.z," ",row.density," ",field)
	for cell in [Vector2i(-1,0),Vector2i(32,0),Vector2i(0,-1),Vector2i(0,32)]:
		if not native.candidates(cell,1703,1.0).ids.is_empty(): failures+=1
	for density in [-1.0,2.0,NAN,INF]:
		if not native.candidates(Vector2i(12,20),1703,density).ids.is_empty(): failures+=1
	ecosystem.seed=1703;ecosystem.density=0.82
	var begin:=Time.get_ticks_usec()
	for sample in range(1000): ecosystem._candidates(Vector2i(12,20))
	var facade_us:=(Time.get_ticks_usec()-begin)/1000.0
	begin=Time.get_ticks_usec()
	for sample in range(1000): native.candidates(Vector2i(12,20),1703,0.82)
	var native_us:=(Time.get_ticks_usec()-begin)/1000.0
	ecosystem.free()
	print("NATIVE_SCATTER ",JSON.stringify({"legacy_cases":reference.size(),"byte_checks":reference.size()*8,"invalid_cases":8,"failures":failures,"facade_mean_us":facade_us,"native_mean_us":native_us}))
	quit(1 if failures else 0)
