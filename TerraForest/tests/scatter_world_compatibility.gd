# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	var native=ClassDB.instantiate("NativeVegetationScatter")
	var legacy=preload("res://tests/fixtures/legacy_scatter.gd").new()
	var cases:=0;var checks:=0;var failures:=0
	var worlds: Array=[]
	for seed_value in [1703,0,-19,9223372036854775807]:
		for density_value in [0.0,0.82,1.0]:
			legacy.seed=seed_value;legacy.density=density_value
			var identities: Dictionary={}
			for z in range(32):
				for x in range(32):
					var key:=Vector2i(x,z)
					var expected: Dictionary=legacy._candidates(key)
					var actual: Dictionary=native.candidates(key,seed_value,density_value)
					cases+=1
					for field in ["points","ids","rotations","scales"]:
						checks+=1
						if expected[field].to_byte_array()!=actual[field].to_byte_array():
							failures+=1
							if failures<=10: print("FAIL ",seed_value," ",density_value," ",key," ",field)
					for id: int in actual.ids:
						if identities.has(id) or id<1+(z*32+x)*36 or id>36+(z*32+x)*36: failures+=1
						identities[id]=true
			worlds.append({"seed":seed_value,"density":density_value,"candidate_ids":identities.size()})
	print("SCATTER_WORLD_COMPATIBILITY ",JSON.stringify({"cells":cases,"byte_checks":checks,"failures":failures,"worlds":worlds,"scope":"all cells of current fixed-size generator; not terrain surface placement or rendering"}))
	quit(1 if failures else 0)
