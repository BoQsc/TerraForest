extends SceneTree
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks.append({"name": label, "pass": value})
	if not value:
		failures += 1
	print("PASS " if value else "FAIL ", label)

func run() -> void:
	if not ClassDB.class_exists("NativeEntityStore"):
		var status: int = GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
		check(status == GDExtensionManager.LOAD_STATUS_OK or status == GDExtensionManager.LOAD_STATUS_ALREADY_LOADED, "Zig/prebuilt godot-cpp extension loads into installed Godot")
	check(ClassDB.class_exists("NativeEntityStore"), "native entity class registered")
	if not ClassDB.class_exists("NativeEntityStore"):
		quit(1)
		return
	var store: RefCounted = ClassDB.instantiate("NativeEntityStore")
	check(not store.configure(0) and not store.configure(262145), "pool capacity validated before allocation")
	check(store.configure(2), "bounded native pool allocated")
	var first: int = store.spawn(Vector3(1, 2, 3), Vector3(6, 0, 0))
	var second: int = store.spawn(Vector3(4, 5, 6), Vector3.ZERO)
	check(first > 0 and second > 0 and first != second, "live handles distinct")
	check(store.spawn(Vector3.ZERO, Vector3.ZERO) == 0, "full pool rejects spawn")
	check(not store.configure(4), "live pool cannot be reconfigured destructively")
	check(not store.step(NAN) and not store.step(0.2) and not store.step(-1), "invalid tick durations rejected")
	check(store.step(0.05) and store.get_position(first).is_equal_approx(Vector3(1.3, 2, 3)), "native tick integrates position")
	check(store.despawn(first) and not store.contains(first) and not store.despawn(first), "despawn invalidates handle exactly once")
	var replacement: int = store.spawn(Vector3(7, 8, 9), Vector3.ZERO)
	check(replacement != first and store.contains(replacement) and not store.contains(first), "reused slot cannot resurrect stale handle")
	check(not store.set_velocity(first, Vector3.ONE) and not store.set_velocity(replacement, Vector3.INF), "invalid handle and nonfinite velocity rejected")
	var buffer: PackedFloat32Array = store.multimesh_transforms()
	check(buffer.size() == 24 and Vector3(buffer[3], buffer[7], buffer[11]).is_equal_approx(store.get_position(second)), "dense removal preserves bulk transform order and layout")
	store.despawn(second)
	store.despawn(replacement)
	check(store.configure(100000), "100000-entity native pool allocated")
	var ids: PackedInt64Array = store.spawn_grid(100000, Vector3.ZERO, 2, Vector3(12, 0, 4))
	check(ids.size() == 100000 and store.statistics()["active"] == 100000, "100000 entities spawned in one native batch")
	check(not store.contains(replacement), "reconfiguration does not revive handles")
	check(store.spawn_grid(1, Vector3.ZERO, 1, Vector3.ZERO).is_empty(), "bulk spawn observes capacity without partial mutation")
	var costs: Array[float] = []
	for i in range(240):
		var start: int = Time.get_ticks_usec()
		var ok: bool = store.step(1.0 / 60.0)
		costs.append(float(Time.get_ticks_usec() - start) / 1000.0)
		if not ok:
			check(false, "bulk tick accepted")
			break
	check(store.statistics()["active"] == 100000 and store.statistics()["ticks"] == 240, "240 native ticks retain bounded entity state")
	check(store.multimesh_transforms().size() == 1200000, "100000 transforms produced in a single native output buffer")
	costs.sort()
	var stats: Dictionary = store.statistics()
	store = null
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/native_runtime.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "engine": Engine.get_version_info(), "stats": stats, "kinematic_step_ms": {"p50": costs[costs.size()/2], "p95": costs[int(costs.size()*0.95)], "max": costs[-1]}, "scope": "CPU-only entity kinematics; not collision, vehicles, networking or rendering FPS"}, "  "))
	file.close()
	quit(0 if failures == 0 else 1)
