# SPDX-License-Identifier: 0BSD
extends SceneTree
const Lakes=preload("res://addons/volumetric_water/lake_world.gd")
const Ecosystem=preload("res://addons/world_ecosystem/world_ecosystem.gd")
class TerrainStub extends Node3D:
	var epoch:=1
	var published_revision:=0
	var pending_edit:=false
class VegetationStub extends Node3D:
	var rows: Dictionary={}
	var writes:=0
	func upsert_chunk(owner: String,ids: PackedInt64Array,_transforms: Array[Transform3D]) -> bool:
		rows[owner]=ids;writes+=1;return true
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var water=Lakes.new();check(water.prepare(),"water addon ready")
	var volume: RefCounted=ClassDB.instantiate("NativeLakeVolume")
	volume.configure(Vector3.ZERO,Vector3i(8,6,8),1.0,3.5,Vector3(2.5,2.5,2.5))
	var field:=PackedFloat32Array()
	for z in 9:
		for y in 7:
			for x in 9: field.append(-1.0 if x==0 or x==8 or z==0 or z==8 or y==0 or x==4 else 1.0)
	check(volume.bake_density(field)==1,"partitioned lake bakes")
	var catalog: RefCounted=ClassDB.instantiate("NativeLakeCatalog")
	var transforms: Array[Transform3D]=[]
	for p: Vector3 in [Vector3(2.5,0.5,2.5),Vector3(2.5,4,2.5),Vector3(6,0.5,2.5),Vector3(70,0.5,2.5)]:
		transforms.append(Transform3D(Basis.IDENTITY,p))
	check(catalog.placement_mask([volume],transforms)==PackedByteArray([1,0,0,0]),"native root mask excludes submerged soil but preserves dry and disconnected roots")
	check(volume.statistics().query_index_bytes==64,"column query index uses one byte per horizontal cell")
	check(catalog.placement_mask([],transforms)==PackedByteArray([0,0,0,0]),"no lakes preserve all roots")
	check(catalog.placement_mask([null],transforms).is_empty(),"invalid volume rejected")
	var large: Array[Transform3D]=[];large.resize(513);large.fill(Transform3D.IDENTITY)
	check(catalog.placement_mask([volume],large).is_empty(),"placement batch has hard 512-root cap")
	var terrain=TerrainStub.new();water.terrain=terrain;water._epoch=1
	var vegetation=VegetationStub.new();var ecosystem=Ecosystem.new();ecosystem.water=water;ecosystem.vegetation=vegetation
	water.exclusion_changed.connect(ecosystem._water_changed)
	var near:=Vector2i.ZERO;var far:=Vector2i(1,0)
	var local: Array[Transform3D]=[transforms[0],transforms[1],transforms[2]]
	var distant: Array[Transform3D]=[transforms[3]]
	ecosystem._samples[near]={"ids":PackedInt64Array([1,2,3]),"transforms":local,"active":PackedInt64Array(),"published":false}
	ecosystem._samples[far]={"ids":PackedInt64Array([4]),"transforms":distant,"active":PackedInt64Array(),"published":false}
	ecosystem._publish_samples(near);ecosystem._publish_samples(far)
	water._install_lake(1,Vector3.ZERO,Vector3i(8,6,8),1.0,3.5,Vector3(2.5,2.5,2.5),volume)
	water._busy_id=1;water._token=17
	water._slice_ready(17,1,1,0)
	check(ecosystem._reconcile.size()==1 and ecosystem._reconcile.has(near),"water publication reconciles only intersecting vegetation owner")
	ecosystem._publish_samples(near)
	check(vegetation.rows["natural/0/0"]==PackedInt64Array([2,3]) and vegetation.rows["natural/1/0"]==PackedInt64Array([4]),"publication removes only submerged root and retains all dry IDs")
	var before: int=vegetation.writes;ecosystem._publish_samples(near)
	check(vegetation.writes==before,"unchanged water mask preserves renderer rows")
	ecosystem._reconcile.clear();water.remove_lake(1)
	check(ecosystem._reconcile.size()==1 and ecosystem._reconcile.has(near),"lake removal only schedules intersecting owner")
	ecosystem._publish_samples(near)
	check(vegetation.rows["natural/0/0"]==PackedInt64Array([1,2,3]),"removal restores original deterministic vegetation candidates")
	water.free();ecosystem.free();vegetation.free();terrain.free()
	quit(1 if failures else 0)
