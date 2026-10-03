# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var structures=preload("res://addons/structures/structures_world.gd").new();root.add_child(structures)
	check(structures.prepare(),"native structures ready")
	var vegetation=preload("res://addons/vegetation/vegetation_world.gd").new();root.add_child(vegetation)
	check(vegetation.enable_trunk_collision() and vegetation.initialize()==OK,"actual vegetation assets and trunk proxies ready")
	var ecosystem=preload("res://addons/world_ecosystem/world_ecosystem.gd").new()
	ecosystem.structures=structures;ecosystem.vegetation=vegetation
	structures.changed.connect(ecosystem._structures_changed)
	var transforms: Array[Transform3D]=[]
	for p in [Vector3(4,0,-25),Vector3(4,0,25),Vector3(4,0,0),Vector3(200,0,0)]: transforms.append(Transform3D(Basis.IDENTITY,p))
	var near:=Vector2i.ZERO;var far:=Vector2i(3,0)
	ecosystem._samples[near]={"ids":PackedInt64Array([1,2,3]),"transforms":transforms.slice(0,3),"active":PackedInt64Array(),"published":false}
	ecosystem._samples[far]={"ids":PackedInt64Array([4]),"transforms":transforms.slice(3,4),"active":PackedInt64Array(),"published":false}
	ecosystem._publish_samples(near);ecosystem._publish_samples(far)
	check(vegetation.renderer.roots.size()==4 and vegetation.trunk_collision.get_ids().size()==4,"initial renderer and physics roots agree")
	var untouched: Transform3D=vegetation.renderer.roots[4].t
	var empty: PackedByteArray=structures.blocks.capture_snapshot()
	var asset=ClassDB.instantiate("NativeBlockPrefab")
	check(asset.compose_frontage([load("res://addons/structures/prefabs/brick_cottage.tres")],2,32,3,1703) and structures.blocks.place_prefab(asset,Vector3i.ZERO,0,false),"frontage placed across two tree roots")
	check(ecosystem._reconcile.has(near),"structure change schedules vegetation reconciliation")
	ecosystem._publish_samples(near);ecosystem._publish_samples(far)
	check(not vegetation.renderer.roots.has(1) and not vegetation.renderer.roots.has(2) and vegetation.renderer.roots.has(3) and vegetation.renderer.roots.has(4),"only intersecting trees removed; street and distant roots survive")
	var ids: PackedInt64Array=vegetation.trunk_collision.get_ids();ids.sort()
	check(ids==PackedInt64Array([3,4]) and vegetation._collision_sync_ok,"removed render roots have no remaining trunk proxy records")
	check(vegetation.renderer.roots[4].t==untouched,"unaffected distant tree transform preserved")
	check(structures.blocks.restore_snapshot(empty),"building removal restores empty structure state")
	ecosystem._publish_samples(near)
	check(vegetation.renderer.roots.size()==4 and vegetation.trunk_collision.get_ids().size()==4,"deterministic trees and trunk records return after structure removal")
	print("FRONTAGE_VEGETATION ",{"failures":failures,"reconciled_owners":ecosystem._reconcile.size(),"root_count":vegetation.renderer.roots.size(),"scope":"actual native block exclusion and vegetation root/proxy membership; no visual rendering or physics contact qualification"})
	structures.changed.disconnect(ecosystem._structures_changed);ecosystem.free();vegetation.free();structures.free()
	quit(1 if failures else 0)
