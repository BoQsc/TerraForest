# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var small=ClassDB.instantiate("NativeBlockPrefab")
	var wide=ClassDB.instantiate("NativeBlockPrefab")
	check(small.configure(PackedInt32Array([-2,-1,3,1,-1,-1,3,2])) and wide.configure(PackedInt32Array([0,0,0,1,4,0,0,3])),"asymmetric source footprints configured")
	var town=ClassDB.instantiate("NativeBlockPrefab")
	check(town.compose_frontage([small,wide],64,8,2,1703) and town.get_cell_count()==256,"128 lots compose through native prefab pipeline")
	var records: PackedInt32Array=town.get_records()
	var clear:=true
	for i in range(0,records.size(),4):
		clear=clear and records[i]>=0 and records[i+1]==0 and (records[i+2]<-6 or records[i+2]>=6)
	check(clear,"street setback and common ground plane preserved for offset sources")
	var repeat=ClassDB.instantiate("NativeBlockPrefab")
	check(repeat.compose_frontage([small,wide],64,8,2,1703) and repeat.get_records()==records,"same seed reproduces exact cell records")
	check(repeat.compose_frontage([small,wide],64,8,2,1704) and repeat.get_records()!=records,"different seed changes building choices")
	check(not town.compose_frontage([small],65,8,2,1) and not town.compose_frontage([small],1,7,2,1) and not town.compose_frontage([small],1,8,2,-1) and town.get_records()==records,"invalid layout requests preserve previous prefab")
	var blocks=ClassDB.instantiate("NativeBlockWorld")
	check(blocks.place_prefab(town,Vector3i(400,50,400),0,false),"generated frontage places in ordinary block world")
	var snapshot: PackedByteArray=blocks.capture_snapshot()
	var restored=ClassDB.instantiate("NativeBlockWorld")
	check(restored.restore_snapshot(snapshot) and restored.capture_snapshot()==snapshot,"generated blocks survive existing world snapshot format")
	check(not blocks.place_prefab(town,Vector3i(400,50,400),0,false) and blocks.capture_snapshot()==snapshot,"occupied placement rejects atomically")
	var cottage: Resource=load("res://addons/structures/prefabs/brick_cottage.tres")
	var village=ClassDB.instantiate("NativeBlockPrefab")
	var start:=Time.get_ticks_usec()
	check(village.compose_frontage([cottage],8,8,3,1703) and village.get_cell_count()==16*cottage.get_cell_count(),"sixteen authored cottages compose without per-building nodes")
	print("FRONTAGE_COTTAGES ",{"cells":village.get_cell_count(),"composition_us":Time.get_ticks_usec()-start,"bounds":village.get_bounds()})
	blocks.free();restored.free()
	quit(0 if failures==0 else 1)
