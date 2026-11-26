# SPDX-License-Identifier: 0BSD
extends "res://addons/player_runtime/storage.gd"
## One shared UI; each container type uses the existing native stack/save store.
const Packs=preload("res://addons/structures/pack_registry.gd")
var stores: Dictionary={}
var collections: Dictionary={}
var names: Dictionary={}
var active_key:=""

func prepare(owner_game: Node, persistence: RefCounted) -> bool:
	game=owner_game; external=true
	if not Packs.discover(): return false
	for key: String in Packs.objects:
		var row: Dictionary=Packs.objects[key]
		if not row.has("container"): continue
		var batch: Node3D=game.structures.model(key)
		var native: RefCounted=ClassDB.instantiate("NativeContainerStore")
		if batch==null or not native.configure(game.player_hud.inventory,Rules.CAPACITY,int(row.container),Rules.PICK_ITEM): return false
		stores[key]=native; collections[batch]=key; names[key]=row.name
		if not persistence.register_component("pack_contents_"+str(row.item),native.capture_storage_snapshot,restore_pack.bind(key),native,native.capture_storage_snapshot()): return false
	return true

func restore_pack(bytes: PackedByteArray, key: String) -> bool:
	close()
	return stores[key].restore_storage_snapshot(bytes)

func restore_protection(enabled: bool) -> bool:
	close(); var ok:=true
	for batch: Node3D in collections:
		var native: RefCounted=stores[collections[batch]]
		for id: int in native.get_ids():
			if not batch.set_removal_protected(id,enabled and native.requires_protection(id)): ok=false
	return ok

func protect(id: int, enabled: bool) -> bool:
	return collection!=null and collection.set_removal_protected(id,enabled)

func aimed_id(shared_hit: Variant=null) -> int:
	var origin: Vector3=game.camera.global_position
	var hit: Dictionary=game.structures.blocks.raycast_scene(origin,origin-game.camera.global_basis.z*3.0,7,[game.player.get_rid()]) if shared_hit==null else shared_hit
	if hit.is_empty() or not collections.has(hit.collider): return 0
	var key: String=collections[hit.collider]
	if opened and key!=active_key: return 0
	if not opened:
		active_key=key; collection=hit.collider; store=stores[key]; container_name=names[key]
	return collection.placement_for_body(hit.rid)

func prompt(_id: int) -> String: return "E · Open "+container_name.trim_prefix("Outdoor ").to_lower()

func try_open(shared_hit: Variant=null) -> bool:
	var result:=super.try_open(shared_hit)
	if result and opened and title_label!=null: title_label.text=container_name.to_upper()
	return result

func _ready() -> void:
	container_name="OBJECT / STORAGE"; super._ready()
	# Shared storage grids and native transactions; no world-instance script nodes.
	for node: Node in panel.find_children("*","Label",true,false):
		if node.text=="CORPSE CONTENTS": node.text="CONTAINER CONTENTS"
		elif node.text.contains("Loot remains saved with this corpse."): node.text="Drag between inventories. Shift-drag moves half. Empty the container before removal."
	set_process(false)

func refresh() -> void:
	super.refresh()
	message.text="F5 saves after closing. Contents remain with this object when moved."
