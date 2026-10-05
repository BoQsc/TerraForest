# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
class TerrainGate extends Node3D:
	var world_ready:=true
	var pending_edit:=false
	var closing:=false
	var stopping:=false
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var state=ClassDB.instantiate("NativeHarvestState")
	var empty: PackedByteArray=state.capture_storage_snapshot()
	check(empty.size()==16 and state.validate_snapshot(empty),"empty state has a canonical versioned snapshot")
	check(not state.mark(0) and not state.mark(-1) and state.mark(2) and not state.mark(2),"stable IDs reject invalid and duplicate harvests")
	check(state.mask(PackedInt64Array([1,2,3]))==PackedByteArray([0,1,0]),"native batch mask only excludes harvested IDs")
	var saved: PackedByteArray=state.capture_storage_snapshot()
	var shared: PackedByteArray=state.capture_storage_snapshot()
	shared.encode_u64(16,77)
	check(state.capture_storage_snapshot()==saved and state.contains(2),"caller mutation cannot corrupt cached canonical snapshot")
	state.mark(3)
	check(state.capture_storage_snapshot()!=saved and saved.decode_u64(8)==1,"mark invalidates cache without mutating previously captured bytes")
	state.unmark(3)
	check(state.capture_storage_snapshot()==saved,"unmark invalidates cache and restores canonical content")
	var invalid:=saved.duplicate();invalid.encode_u64(16,0)
	check(not state.restore_storage_snapshot(invalid) and state.contains(2),"invalid restore leaves live exclusions intact")
	check(state.unmark(2) and state.restore_storage_snapshot(saved) and state.contains(2),"rollback and snapshot restore preserve exact identity")
	var restored: PackedByteArray=saved.duplicate()
	state.restore_storage_snapshot(restored);restored.encode_u64(16,99)
	check(state.capture_storage_snapshot()==saved,"restored cache remains isolated from subsequent input mutation")
	var huge:=PackedInt64Array();huge.resize(4097)
	check(state.mask(huge).is_empty(),"oversized batches are rejected")
	state.restore_storage_snapshot(empty)
	for id in range(1,262145): state.mark(id)
	check(not state.mark(262145) and state.contains(262144),"persistent exclusion capacity rejects overflow without evicting old IDs")
	var full: PackedByteArray=state.capture_storage_snapshot()
	check(full.size()==2097168 and state.validate_snapshot(full),"full capacity has bounded canonical storage")
	full.encode_u64(24,1)
	check(not state.validate_snapshot(full),"duplicate snapshot identities are rejected")
	state.restore_storage_snapshot(empty)
	var oracle:=PackedInt64Array([9223372036854775807,1,256,65536,4294967296,72057594037927936])
	for i in range(300): oracle.append(2+i*17592186044417)
	for id in oracle: state.mark(id)
	oracle.sort()
	var ordered: PackedByteArray=state.capture_storage_snapshot()
	var matches: bool=state.validate_snapshot(ordered) and ordered.decode_u64(8)==oracle.size()
	for i in range(oracle.size()): matches=matches and ordered.decode_s64(16+i*8)==oracle[i]
	check(matches,"canonical sorting matches independent oracle across all eight ID bytes")
	var ecosystem=load("res://addons/world_ecosystem/world_ecosystem.gd").new()
	var persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	check(ecosystem.prepare_persistence(persistence),"harvest state registers in compound persistence")
	var vegetation=load("res://addons/vegetation/vegetation_world.gd").new()
	root.add_child(vegetation);vegetation.ready_to_render=true
	check(vegetation.enable_trunk_collision(),"fixture uses actual native trunk collision")
	ecosystem.vegetation=vegetation
	var transforms: Array[Transform3D]=[Transform3D.IDENTITY,Transform3D(Basis.IDENTITY,Vector3(10,0,0))]
	var key:=Vector2i.ZERO
	ecosystem._replace_samples(key,PackedInt64Array([1,2]),transforms)
	check(vegetation.renderer.roots.size()==2,"both unharvested roots publish")
	ecosystem.harvest_state.mark(1)
	ecosystem._publish_samples(key)
	check(not vegetation.renderer.roots.has(1) and vegetation.renderer.roots.has(2) and vegetation.trunk_collision.get_ids()==PackedInt64Array([2]),"harvest mask removes exactly one visual root and collider")
	var sections: Dictionary=persistence._capture().sections
	ecosystem.reset()
	ecosystem._replace_samples(key,PackedInt64Array([1,2]),transforms)
	check(not vegetation.renderer.roots.has(1),"cell eviction and regeneration cannot respawn harvested ID")
	ecosystem.harvest_state.unmark(1)
	persistence._restore(sections,1)
	ecosystem._publish_samples(key)
	check(not vegetation.renderer.roots.has(1) and vegetation.renderer.roots.has(2),"compound provider restore reinstates only saved exclusions")
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var inventory=ClassDB.instantiate("NativePlayerInventory")
	inventory.register_item(102,999)
	var empty_inventory: PackedByteArray=inventory.capture_storage_snapshot()
	var gate:=TerrainGate.new();ecosystem.terrain=gate
	for field in ["world_ready","pending_edit","closing","stopping"]:
		gate.set(field,field!="world_ready")
		var denied: Dictionary=ecosystem.harvest_root(2,inventory)
		check(not denied.ok and denied.reason=="World updating; try again" and vegetation.renderer.roots.has(2) and not ecosystem.harvest_state.contains(2) and inventory.capture_storage_snapshot()==empty_inventory,"addon rejects harvest during "+field+" gate without mutation")
		gate.set(field,field=="world_ready")
	for field in ["_resample","_pending_cells","_reconcile"]:
		ecosystem.get(field)[key]=true
		var denied: Dictionary=ecosystem.harvest_root(2,inventory)
		check(not denied.ok and denied.reason=="Vegetation updating; try again" and vegetation.renderer.roots.has(2) and not ecosystem.harvest_state.contains(2) and inventory.capture_storage_snapshot()==empty_inventory,"addon rejects stale owner during "+field)
		ecosystem.get(field).erase(key)
	ecosystem._reconcile[key]=true
	ecosystem._publish_samples(key)
	check(not ecosystem._reconcile.has(key),"successful unchanged reconciliation clears harvest gate")
	ecosystem.terrain=null;gate.free()
	inventory.grant(102,32*999,inventory.snapshot().revision)
	check(not ecosystem.harvest_root(2,inventory).ok and vegetation.renderer.roots.has(2) and not ecosystem.harvest_state.contains(2),"full inventory preserves tree and harvest state")
	inventory.consume_items(PackedInt64Array([102,4]),inventory.snapshot().revision)
	check(ecosystem.harvest_root(2,inventory).ok and ecosystem.harvest_state.contains(2) and not vegetation.renderer.roots.has(2),"harvesting grants wood and removes the active tree")
	check(inventory.can_afford(PackedInt64Array([102,32*999]),inventory.snapshot().revision).ok,"harvest grants exactly four wood")
	var after: PackedByteArray=inventory.capture_storage_snapshot()
	check(not ecosystem.harvest_root(2,inventory).ok and inventory.capture_storage_snapshot()==after,"repeated harvesting cannot duplicate wood")
	ecosystem.free();vegetation.free()
	print("HARVEST_STATE ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
