# SPDX-License-Identifier: 0BSD
extends SceneTree

# Frozen pre-native priority algorithm, used only as a compatibility oracle.
func legacy(center: Vector2i, radius_world: float, limit: int) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var radius: int = ceili(radius_world / 64.0)
	for z in range(maxi(0, center.y - radius), mini(31, center.y + radius) + 1):
		for x in range(maxi(0, center.x - radius), mini(31, center.x + radius) + 1):
			candidates.append(Vector2i(x, z))
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = (a - center).length_squared()
		var db: int = (b - center).length_squared()
		return da < db if da != db else (a.y * 32 + a.x < b.y * 32 + b.x))
	candidates.resize(mini(candidates.size(), limit))
	return candidates

func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	var native = ClassDB.instantiate("NativeVegetationScatter")
	var cases := 0
	var failures := 0
	for z in range(-1, 33):
		for x in range(-1, 33):
			for radius in [0.0, 64.0, 65.0, 384.0, 768.0]:
				for limit in [0, 9, 169, 625]:
					cases += 1
					if native.wanted_cells(Vector2i(x,z),radius,limit) != legacy(Vector2i(x,z),radius,limit):
						failures += 1
	for args in [[NAN,169],[INF,169],[-1.0,169],[769.0,169],[384.0,-1],[384.0,626]]:
		cases += 1
		if not native.wanted_cells(Vector2i(16,16),args[0],args[1]).is_empty(): failures += 1
	for center in [Vector2i(-2147483648,0),Vector2i(2147483647,31),Vector2i(0,-2147483648),Vector2i(31,2147483647)]:
		cases += 1
		if not native.wanted_cells(center,768.0,625).is_empty(): failures += 1
	# Exercise the facade, including order used for request admission.
	var ecosystem = load("res://addons/world_ecosystem/world_ecosystem.gd").new()
	ecosystem.stream_radius = 384.0
	ecosystem.max_resident_cells = 169
	ecosystem._refresh(Vector2i(12,20))
	cases += 1
	if ecosystem._wanted.keys() != legacy(Vector2i(12,20),384.0,169): failures += 1
	ecosystem.free()
	var start := Time.get_ticks_usec()
	for i in range(1000): legacy(Vector2i(16,16),384.0,169)
	var legacy_us := Time.get_ticks_usec()-start
	start = Time.get_ticks_usec()
	for i in range(1000): native.wanted_cells(Vector2i(16,16),384.0,169)
	print("PRIORITY microbenchmark 1000 calls: legacy_us=",legacy_us," native_us=",Time.get_ticks_usec()-start)
	print("PRIORITY cases=",cases," failures=",failures)
	quit(0 if failures==0 else 1)
