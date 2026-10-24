# SPDX-License-Identifier: 0BSD
extends Node3D
signal changed
## Scene orchestration only: native stores, spatial queries and batched rendering.
## Static authored supplies; no per-pickup nodes or active rigid bodies.
const ITEMS := {1:"Pickaxe",2:"Hatchet",3:"Repair hammer",4:"Assembly tool",5:"Shovel",101:"Brick",102:"Wood",103:"Concrete",104:"Metal",201:"Stone",202:"Iron ore",203:"Copper ore",204:"Plant",205:"Grass clump",206:"White wildflower",207:"Golden wildflower",208:"Violet wildflower",209:"Low bush",210:"Dry twigs",211:"Topsoil",301:"Woven hood",302:"Woven vest",303:"Woven footwraps",401:"Water bucket",212:"Woody bush",501:"Vehicle"}
const COLORS := {101: Color("b57052"), 102: Color("b99563"), 103: Color("b4bec4"), 104: Color("729da9"), 201: Color("7f858c"), 202: Color("965e43"), 203: Color("bc7950"), 204: Color("557538"), 205: Color("677e3e")}
var stores: Dictionary = {}
var stacks: Dictionary = {}
var renderers: Dictionary = {}
var render_status: Dictionary = {}
var _elapsed := 0.0
var _dirty := true
var _transferring := false
var _persistence: RefCounted

func drop_one(inventory: RefCounted, slot: int, revision: int, point: Vector3) -> Dictionary:
	return drop_stack(inventory,slot,revision,point,1)

func drop_stack(inventory: RefCounted, slot: int, revision: int, point: Vector3, count: int) -> Dictionary:
	if _transferring or inventory == null or not point.is_finite():
		return {"ok":false,"reason":"Supply drop unavailable"}
	var state: Dictionary = inventory.snapshot()
	if state.revision != revision or slot < 0 or slot >= state.slots.size():
		return {"ok":false,"reason":"Inventory changed; select the supply again"}
	var item: int = state.slots[slot].item
	if item>=401 and item<=411:item=401
	if not stores.has(item) or count<1 or state.slots[slot].count < count:
		return {"ok":false,"reason":"Select a carried item to drop"}
	# Native calls emit no callbacks. Reserve the world record before debiting;
	# capacity failure therefore leaves inventory contents AND revision intact.
	_transferring = true
	var handle: int = stores[item].spawn(point, Vector3.ZERO)
	if handle == 0:
		_transferring = false
		return {"ok":false,"reason":"Supply capacity reached"}
	var id: int = stores[item].persistent_id(handle)
	var consumed: Dictionary = stacks[item].deposit(id,inventory,slot,count,revision,stacks[item].snapshot(id).store_revision)
	if not consumed.ok:
		stores[item].despawn(handle)
		_transferring = false
		return {"ok":false,"reason":"Inventory changed; drop cancelled"}
	_dirty = true
	changed.emit() # Observers see both sides committed; nested drops are rejected.
	_transferring = false
	return {"ok":true,"id":id,"item":item,"reason":"Dropped %d %s"%[count,ITEMS[item]]}

func prepare(persistence: RefCounted) -> bool:
	if not stores.is_empty(): return persistence==_persistence and stores.size()==ITEMS.size() and renderers.size()==ITEMS.size()
	if persistence==null or not persistence.has_method("register_components"):return false
	if not ClassDB.class_exists("NativeEntityStore"):
		GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	if not ClassDB.class_exists("NativeEntityRenderer"): return false
	if not ClassDB.class_exists("NativePlayerInventory"):GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var schema: RefCounted=ClassDB.instantiate("NativePlayerInventory")
	for bucket_id in range(402,412):schema.register_item(bucket_id,1)
	for item: int in ITEMS:
		schema.register_item(item,1 if item<100 or item>=301 else 999)
		if item in preload("res://addons/player_runtime/durability_catalog.gd").TOOLS:schema.register_durable(item,preload("res://addons/player_runtime/durability_catalog.gd").TOOLS[item])
		if item==501:schema.register_durable(item,300)
	var next_stacks:Dictionary={};var next_stores:Dictionary={};var next_renderers:Dictionary={}
	var components:Array[Dictionary]=[]
	for item: int in ITEMS:
		var stack: RefCounted=ClassDB.instantiate("NativeContainerStore")
		if not stack.configure(schema,4096):_discard_renderers(next_renderers);return false
		next_stacks[item]=stack
		components.append({"name":"pickup_stacks_%d"%item,"capture":stack.capture_storage_snapshot,"restore":stack.restore_storage_snapshot,"validator":stack,"empty":stack.capture_storage_snapshot()})
		var store: RefCounted = ClassDB.instantiate("NativeEntityStore")
		if not store.configure(4096): _discard_renderers(next_renderers);return false
		next_stores[item] = store
		components.append({"name":"pickups_%d"%item,"capture":store.capture_storage_snapshot,"restore":_restore.bind(item),"validator":store,"empty":store.capture_storage_snapshot()})
		var mesh: Mesh=preload("res://addons/volumetric_water/bucket_model.gd").mesh() if item==401 else (preload("res://addons/vehicle_runtime/vehicle_item.gd").mesh() if item==501 else load("res://addons/player_runtime/art/drops/%d.res"%item))
		if mesh==null:_discard_renderers(next_renderers);return false
		var renderer: MultiMeshInstance3D = ClassDB.instantiate("NativeEntityRenderer")
		if not renderer.configure(store, mesh, 256):
			renderer.free(); _discard_renderers(next_renderers);return false
		renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		next_renderers[item] = renderer
	if not persistence.register_components(components):_discard_renderers(next_renderers);return false
	_persistence=persistence
	stores=next_stores;stacks=next_stacks;renderers=next_renderers
	for renderer:Node in renderers.values():add_child(renderer)
	return true

func _discard_renderers(pending:Dictionary)->void:
	for renderer:Node in pending.values():renderer.free()

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

func aimed(from: Vector3,to: Vector3,reachable: Callable) -> Dictionary:
	if _transferring or not from.is_finite() or not to.is_finite() or not reachable.is_valid():return {"ok":false,"reason":"Pickup unavailable"}
	var budget:=1024;var visited:=0;var queries:=0;var best:=1.0;var selected: Dictionary={"ok":false,"reason":"No aimed pickup"}
	# Fixed catalog orchestration only; native spatial cells and intersections.
	for item: int in stores:
		if budget<=0:return {"ok":false,"reason":"Pickup area is too crowded","visited":visited,"queries":queries}
		var query: Dictionary=stores[item].query_segment(to_local(from),to_local(to),0.32,budget)
		queries+=1;visited+=int(query.visited)
		if not query.ok or not query.complete:return {"ok":false,"reason":"Pickup area is too crowded","visited":visited,"queries":queries}
		budget-=int(query.visited)
		if query.handle>0 and (not selected.ok or query.fraction<best):
			best=query.fraction;selected={"ok":true,"item":item,"handle":query.handle,"position":from.lerp(to,best)}
	if selected.ok:
		var center: Vector3=to_global(stores[selected.item].get_position(selected.handle))
		if not reachable.call(center):return {"ok":false,"reason":"Pickup obstructed","visited":visited,"queries":queries}
	selected.visited=visited;selected.queries=queries
	return selected

func collect_aimed(from: Vector3,to: Vector3,inventory: RefCounted,reachable: Callable) -> Dictionary:
	var candidate:=aimed(from,to,reachable)
	if not candidate.ok:return candidate
	return _collect(candidate.item,candidate.handle,inventory)

func collect_near(point: Vector3, inventory: RefCounted, reachable: Callable) -> Dictionary:
	# Explicit keypress only; at most ITEMS.size() x 64 candidates. Never a per-frame scan.
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
	return _collect(best_item,best_handle,inventory)

func _collect(best_item: int,best_handle: int,inventory: RefCounted) -> Dictionary:
	if _transferring or inventory==null or not stores.has(best_item) or not stores[best_item].contains(best_handle):return {"ok":false,"reason":"Pickup unavailable"}
	_transferring=true
	var id: int=stores[best_item].persistent_id(best_handle)
	var box: Dictionary=stacks[best_item].snapshot(id)
	var result: Dictionary
	if stacks[best_item].has_contents(id):
		result=stacks[best_item].withdraw(id,inventory,0,box.slots[0].count,inventory.snapshot().revision,box.store_revision)
	else:result=inventory.grant(best_item,1,inventory.snapshot().revision) # Legacy/authored single pickup.
	if not result.ok:
		_transferring=false;return {"ok": false, "reason": "Inventory full or unavailable"}
	# Single main-thread transaction: grant emits no callbacks; this handle is live.
	stores[best_item].despawn(best_handle); _dirty = true
	# Emit after both halves commit so observers capture a consistent world.
	changed.emit()
	_transferring=false
	return {"ok": true, "item": best_item, "reason": "Collected " + ITEMS[best_item]}
