# SPDX-License-Identifier: 0BSD
extends Node3D
signal changed
## Scene orchestration only: native stores, spatial queries and batched rendering.
## Static authored supplies; no per-pickup nodes or active rigid bodies.
const ITEMS := {101: "Brick", 102: "Wood", 103: "Concrete", 104: "Metal"}
const COLORS := [Color("b57052"), Color("b99563"), Color("b4bec4"), Color("729da9")]
var stores: Dictionary = {}
var renderers: Dictionary = {}
var render_status: Dictionary = {}
var _elapsed := 0.0
var _dirty := true

func prepare(persistence: RefCounted) -> bool:
	if not stores.is_empty(): return true
	if not ClassDB.class_exists("NativeEntityStore"):
		GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	if not ClassDB.class_exists("NativeEntityRenderer"): return false
	for item: int in ITEMS:
		var store: RefCounted = ClassDB.instantiate("NativeEntityStore")
		if not store.configure(4096): return false
		stores[item] = store
		if not persistence.register_component("pickups_%d" % item, store.capture_storage_snapshot, _restore.bind(item), store, store.capture_storage_snapshot()): return false
		var mesh := BoxMesh.new(); mesh.size = Vector3.ONE * 0.35
		var material := StandardMaterial3D.new()
		material.albedo_color = COLORS[item - 101]; material.roughness = 0.8
		mesh.material = material
		var renderer: MultiMeshInstance3D = ClassDB.instantiate("NativeEntityRenderer")
		if not renderer.configure(store, mesh, 256):
			renderer.free(); return false
		renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(renderer); renderers[item] = renderer
	return true

func _restore(data: PackedByteArray, item: int) -> bool:
	if not stores[item].restore_storage_snapshot(data): return false
	_dirty = true
	return true

func spawn(item: int, point: Vector3) -> int:
	if not stores.has(item): return 0
	var handle: int = stores[item].spawn(point, Vector3.ZERO)
	if handle == 0: return 0
	_dirty = true
	changed.emit()
	return stores[item].persistent_id(handle)

func update_view(delta: float, focus: Vector3, enabled: bool) -> void:
	visible = enabled
	if not enabled: return
	_elapsed += delta
	if not _dirty and _elapsed < 0.1: return
	_elapsed = 0; _dirty = false
	for item: int in stores:
		render_status[item] = renderers[item].refresh(to_local(focus), 64.0, 4096)

func collect_near(point: Vector3, inventory: RefCounted, reachable: Callable) -> Dictionary:
	# Explicit keypress only; at most 4 x 64 candidates. Never a per-frame scan.
	var best_item := 0; var best_handle := 0; var best_distance := INF
	for item: int in stores:
		var query: Dictionary = stores[item].query_sphere(to_local(point), 2.5, 64, 256)
		if not query.ok or not query.complete: return {"ok": false, "reason": "Pickup area is too crowded"}
		for handle: int in query.ids:
			var position: Vector3 = to_global(stores[item].get_position(handle))
			var distance := point.distance_squared_to(position)
			if distance < best_distance and reachable.call(position):
				best_item = item; best_handle = handle; best_distance = distance
	if best_handle == 0: return {"ok": false, "reason": "No reachable material within 2.5 m"}
	var result: Dictionary = inventory.grant(best_item, 1, inventory.snapshot().revision)
	if not result.ok: return {"ok": false, "reason": "Inventory full or unavailable"}
	# Single main-thread transaction: grant emits no callbacks; this handle is live.
	stores[best_item].despawn(best_handle); _dirty = true
	# Emit after both halves commit so observers capture a consistent world.
	changed.emit()
	return {"ok": true, "item": best_item, "reason": "Collected " + ITEMS[best_item]}
