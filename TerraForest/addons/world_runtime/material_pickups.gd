# SPDX-License-Identifier: 0BSD
extends Node3D
signal changed
## Scene orchestration only: native stores, spatial queries and batched rendering.
## Authored supplies stay static; player drops may use bounded native physics.
const ITEMS := {1:"Pickaxe",2:"Hatchet",3:"Repair hammer",4:"Assembly tool",5:"Shovel",6:"Wooden torch",101:"Brick",102:"Wood",103:"Concrete",104:"Metal",201:"Stone",202:"Iron ore",203:"Copper ore",204:"Plant",205:"Grass clump",206:"White wildflower",207:"Golden wildflower",208:"Violet wildflower",209:"Low bush",210:"Dry twigs",211:"Topsoil",301:"Woven hood",302:"Woven vest",303:"Woven footwraps",304:"Trail hat",305:"Trail jerkin",306:"Trail boots",401:"Water bucket",212:"Woody bush",213:"Lockpick",214:"Field manual",215:"Unsent letter",216:"Survey journal",217:"Tinned beans",218:"Trail bread",219:"Dried berries",224:"Metal offcuts",225:"Cloth scraps",226:"Copper wire",227:"Loose fasteners",501:"Vehicle"}
const COLORS := {101: Color("b57052"), 102: Color("b99563"), 103: Color("b4bec4"), 104: Color("729da9"), 201: Color("7f858c"), 202: Color("965e43"), 203: Color("bc7950"), 204: Color("557538"), 205: Color("677e3e")}
const ItemCatalog=preload("res://addons/player_runtime/item_catalog.gd")
# ITEMS retains the historical save-section/batch identities. All other carried
# items share one bounded batch, so new catalog entries add no save providers.
const GENERIC_ITEM:=0
var stores: Dictionary = {}
var stacks: Dictionary = {}
var renderers: Dictionary = {}
var render_status: Dictionary = {}
var _elapsed := 0.0
var _dirty := true
var _transferring := false
var _persistence: RefCounted
var _schema: RefCounted
var _aimed_identity:=0
var _aimed_batch:=0
var _aimed_carried:=0
var physics:RefCounted
var physics_enabled:=true
var physics_settings_path:="user://item_drops.cfg"
var persist_physics_settings:=false

func configure_physics(excluded:RID,persist_settings:bool)->bool:
	persist_physics_settings=persist_settings
	if persist_settings and not physics_settings_path.is_empty():
		var config:=ConfigFile.new()
		if config.load(physics_settings_path)==OK:physics_enabled=bool(config.get_value("items","physical_drops",true))
	return physics!=null and physics.configure(get_world_3d().space,excluded,global_transform)

func set_physics_enabled(value:bool)->void:
	physics_enabled=value
	if persist_physics_settings and not physics_settings_path.is_empty():
		var config:=ConfigFile.new();config.load(physics_settings_path)
		config.set_value("items","physical_drops",value);config.save(physics_settings_path)

func step_physics(delta:float,run:bool,ready:Callable)->Dictionary:
	var result:Dictionary=physics.step(delta,run,ready)
	if result.get("changed",false):_dirty=true;changed.emit()
	return result

func item_name(item:int)->String:
	return ItemCatalog.item_name(item)

func store_item(item:int)->int:
	if item>=401 and item<=411:return 401
	return item if ITEMS.has(item) else GENERIC_ITEM

func _carried_item(batch:int,handle:int)->int:
	if batch!=GENERIC_ITEM and batch!=401:return batch
	var identity:int=stores[batch].persistent_id(handle)
	# One derived label cache, invalidated by restore. Pickup contents only change
	# through drop/collect here; collection always reads the live native record.
	if _aimed_identity==identity and _aimed_batch==batch:return _aimed_carried
	var box:Dictionary=stacks[batch].snapshot(identity)
	_aimed_identity=identity;_aimed_batch=batch
	_aimed_carried=int(box.slots[0].item) if int(box.slots[0].count)>0 else batch
	return _aimed_carried

func drop_one(inventory: RefCounted, slot: int, revision: int, point: Vector3) -> Dictionary:
	return drop_stack(inventory,slot,revision,point,1)

func drop_stack(inventory: RefCounted, slot: int, revision: int, point: Vector3, count: int, simulate:bool=false, velocity:Vector3=Vector3.ZERO) -> Dictionary:
	if _transferring or inventory == null or not point.is_finite():
		return {"ok":false,"reason":"Supply drop unavailable"}
	var state: Dictionary = inventory.snapshot()
	if state.revision != revision or slot < 0 or slot >= state.slots.size():
		return {"ok":false,"reason":"Inventory changed; select the supply again"}
	var carried: int = state.slots[slot].item
	var item:=store_item(carried)
	if carried<=0 or not stores.has(item) or count<1 or state.slots[slot].count < count:
		return {"ok":false,"reason":"Select a carried item to drop"}
	if simulate and (physics==null or not physics.can_launch()):return {"ok":false,"reason":"Too many moving drops; wait for them to settle"}
	# Native calls emit no callbacks. Reserve the world record before debiting;
	# capacity failure therefore leaves inventory contents AND revision intact.
	_transferring = true
	var handle: int = stores[item].spawn(point, Vector3.ZERO)
	if handle == 0:
		_transferring = false
		return {"ok":false,"reason":"Supply capacity reached"}
	var id: int = stores[item].persistent_id(handle)
	if simulate and not physics.launch(item,handle,velocity):
		stores[item].despawn(handle);_transferring=false
		return {"ok":false,"reason":"Physical drop unavailable; item retained"}
	var consumed: Dictionary = stacks[item].deposit(id,inventory,slot,count,revision,stacks[item].snapshot(id).store_revision)
	if not consumed.ok:
		if simulate:physics.forget(item,id)
		stores[item].despawn(handle)
		_transferring = false
		return {"ok":false,"reason":"Inventory changed; drop cancelled"}
	_dirty = true
	changed.emit() # Observers see both sides committed; nested drops are rejected.
	_transferring = false
	return {"ok":true,"id":id,"item":carried,"store_item":item,"reason":"Dropped %d %s"%[count,item_name(carried)]}

func prepare(persistence: RefCounted, inventory_schema:RefCounted=null) -> bool:
	if not stores.is_empty(): return persistence==_persistence and (inventory_schema==null or inventory_schema==_schema) and stores.size()==ITEMS.size()+1 and renderers.size()==ITEMS.size()+1
	if persistence==null or not persistence.has_method("register_components"):return false
	if not ClassDB.class_exists("NativeEntityStore"):
		GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	if not ClassDB.class_exists("NativeEntityRenderer"): return false
	if not ClassDB.class_exists("NativePlayerInventory"):GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var schema:RefCounted=ItemCatalog.create_inventory() if inventory_schema==null else inventory_schema
	if schema==null:return false
	var next_stacks:Dictionary={};var next_stores:Dictionary={};var next_renderers:Dictionary={}
	var next_physics:RefCounted=ClassDB.instantiate("NativePickupPhysics")
	var components:Array[Dictionary]=[]
	var batches:Array=ITEMS.keys();batches.append(GENERIC_ITEM)
	for item: int in batches:
		var stack: RefCounted=ClassDB.instantiate("NativeContainerStore")
		if not stack.configure(schema,4096):_discard_renderers(next_renderers);return false
		next_stacks[item]=stack
		components.append({"name":"pickup_stacks_%d"%item,"capture":stack.capture_storage_snapshot,"restore":stack.restore_storage_snapshot,"validator":stack,"empty":stack.capture_storage_snapshot()})
		var store: RefCounted = ClassDB.instantiate("NativeEntityStore")
		if not store.configure(4096): _discard_renderers(next_renderers);return false
		next_stores[item] = store
		if not next_physics.bind_store(item,store):_discard_renderers(next_renderers);return false
		components.append({"name":"pickups_%d"%item,"capture":store.capture_storage_snapshot,"restore":_restore.bind(item),"validator":store,"empty":store.capture_storage_snapshot()})
		var mesh: Mesh=_generic_mesh() if item==GENERIC_ITEM else preload("res://addons/player_runtime/salvage_mesh.gd").mesh(item) if item in [224,225,226,227] else preload("res://addons/volumetric_water/bucket_model.gd").mesh() if item==401 else (preload("res://addons/vehicle_runtime/vehicle_item.gd").mesh() if item==501 else load("res://addons/player_runtime/art/drops/%d.res"%item))
		if mesh==null:_discard_renderers(next_renderers);return false
		var renderer: MultiMeshInstance3D = ClassDB.instantiate("NativeEntityRenderer")
		if not renderer.configure(store, mesh, 256):
			renderer.free(); _discard_renderers(next_renderers);return false
		renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		next_renderers[item] = renderer
	components.append({"name":"pickup_physics","capture":next_physics.capture_storage_snapshot,"restore":next_physics.restore_storage_snapshot,"validator":next_physics,"empty":next_physics.capture_storage_snapshot()})
	if not persistence.register_components(components):_discard_renderers(next_renderers);return false
	_persistence=persistence
	_schema=schema
	physics=next_physics
	stores=next_stores;stacks=next_stacks;renderers=next_renderers
	for renderer:Node in renderers.values():add_child(renderer)
	return true

func _generic_mesh()->ArrayMesh:
	# Original code-built parcel silhouette; no item-specific art is required.
	var box:=BoxMesh.new();box.size=Vector3(.28,.18,.22)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("bb9765");material.roughness=.9
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(box,0,Transform3D.IDENTITY);surface.set_material(material)
	return surface.commit()

func _discard_renderers(pending:Dictionary)->void:
	for renderer:Node in pending.values():renderer.free()

func _restore(data: PackedByteArray, item: int) -> bool:
	if physics!=null:physics.reset()
	if not stores[item].restore_storage_snapshot(data): return false
	_aimed_identity=0
	_dirty = true
	return true

func spawn(item: int, point: Vector3) -> int:
	if not ITEMS.has(item):
		# Native seeding validates against the same schema, including future items.
		if _transferring or not point.is_finite() or not stores.has(GENERIC_ITEM):return 0
		var handle:int=stores[GENERIC_ITEM].spawn(point,Vector3.ZERO)
		if handle==0:return 0
		var id:int=stores[GENERIC_ITEM].persistent_id(handle)
		if not stacks[GENERIC_ITEM].seed_contents(id,PackedInt64Array([item,1])):
			stores[GENERIC_ITEM].despawn(handle);return 0
		_transferring=true;_dirty=true;changed.emit();_transferring=false
		return id
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
	# Fixed legacy batches plus one universal batch; native spatial queries.
	for item: int in stores:
		if budget<=0:return {"ok":false,"reason":"Pickup area is too crowded","visited":visited,"queries":queries}
		var query: Dictionary=stores[item].query_segment(to_local(from),to_local(to),0.32,budget)
		queries+=1;visited+=int(query.visited)
		if not query.ok or not query.complete:return {"ok":false,"reason":"Pickup area is too crowded","visited":visited,"queries":queries}
		budget-=int(query.visited)
		if query.handle>0 and (not selected.ok or query.fraction<best):
			best=query.fraction;selected={"ok":true,"item":item,"store_item":item,"handle":query.handle,"position":from.lerp(to,best)}
	if selected.ok:
		var center: Vector3=to_global(stores[selected.store_item].get_position(selected.handle))
		if not reachable.call(center):return {"ok":false,"reason":"Pickup obstructed","visited":visited,"queries":queries}
		selected.item=_carried_item(selected.store_item,selected.handle)
	selected.visited=visited;selected.queries=queries
	return selected

func collect_aimed(from: Vector3,to: Vector3,inventory: RefCounted,reachable: Callable) -> Dictionary:
	var candidate:=aimed(from,to,reachable)
	if not candidate.ok:return candidate
	return _collect(candidate.store_item,candidate.handle,inventory)

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
	var carried:int=int(box.slots[0].item) if int(box.slots[0].count)>0 else best_item
	if carried<=0:_transferring=false;return {"ok":false,"reason":"Pickup contents unavailable"}
	var result: Dictionary
	if stacks[best_item].has_contents(id):
		result=stacks[best_item].withdraw(id,inventory,0,box.slots[0].count,inventory.snapshot().revision,box.store_revision)
	else:result=inventory.grant(best_item,1,inventory.snapshot().revision) # Legacy/authored single pickup.
	if not result.ok:
		_transferring=false;return {"ok": false, "reason": "Inventory full or unavailable"}
	# Single main-thread transaction: grant emits no callbacks; this handle is live.
	if physics!=null:physics.forget(best_item,id)
	stores[best_item].despawn(best_handle); _dirty = true
	# Emit after both halves commit so observers capture a consistent world.
	changed.emit()
	_transferring=false
	return {"ok": true, "item": carried, "reason": "Collected " + item_name(carried)}
