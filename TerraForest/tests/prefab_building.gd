# SPDX-License-Identifier: 0BSD
extends SceneTree
## Short CPU authoring check. Does not bake/render or measure city frame rate.
const Library=preload("res://addons/structures/prefab_library.gd")
var failures:=0
var report: Dictionary={"scope":"native building authoring; no rendering or physics baking","dimensions":[64,64,64],"floors":16,"timings_ms":{}}
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var blocks=ClassDB.instantiate("NativeBlockWorld")
	blocks.configure_history(16*1024*1024,128)
	var records:=PackedInt32Array()
	# Floors, windowed perimeter walls and an internal stair column.
	for y in 64:
		for z in 64:
			for x in 64:
				var floor_cell:=y%4==0 or y==63
				var wall: bool=(x==0 or x==63 or z==0 or z==63) and (y%4==3 or x%4==0 or z%4==0)
				var stair: bool=x>=29 and x<=32 and z==28+y%4
				if not floor_cell and not wall and not stair: continue
				var shape:=3 if stair else 1
				var rotation:=int(y/4)%4 if stair else 0
				var material:=1 if stair else (2 if floor_cell else 0)
				records.append_array(PackedInt32Array([x,y,z,shape+(rotation<<3)+(material<<5)]))
	report.cells=records.size()/4
	var start:=Time.get_ticks_usec()
	check(blocks.set_cells(records),"16-storey source building authored")
	report.timings_ms.source_write=(Time.get_ticks_usec()-start)/1000.0
	var source: PackedByteArray=blocks.capture_snapshot()
	start=Time.get_ticks_usec()
	var native_asset: Resource=blocks.capture_prefab(Vector3i.ZERO,Vector3i(64,64,64))
	report.timings_ms.native_capture=(Time.get_ticks_usec()-start)/1000.0
	check(native_asset!=null and native_asset.get_cell_count()==report.cells,"maximum-volume selection captures every occupied building cell")
	check(blocks.capture_snapshot()==source,"large capture preserves source snapshot")
	var library=Library.new();library.directory="user://tests/prefab_building_%d" % Time.get_ticks_usec()
	library.select_corner(true,Vector3i(63,63,63));library.select_corner(false,Vector3i.ZERO)
	start=Time.get_ticks_usec()
	var result: Dictionary=library.capture(blocks,"Sixteen-storey tower")
	report.timings_ms.capture_and_save=(Time.get_ticks_usec()-start)/1000.0
	check(result.ok,"building captured and saved through authoring library")
	if not result.ok: blocks.free();quit(1);return
	var file:=FileAccess.open(result.path,FileAccess.READ);report.asset_bytes=file.get_length();file.close()
	var reopened=Library.new();reopened.directory=library.directory
	start=Time.get_ticks_usec();reopened.load_library();report.timings_ms.library_reload=(Time.get_ticks_usec()-start)/1000.0
	check(reopened.assets.size()==1 and reopened.assets[0].get_records()==native_asset.get_records(),"large prefab disk roundtrip preserves exact records")
	var origin:=Vector3i(192,0,128)
	start=Time.get_ticks_usec()
	check(blocks.place_prefab(reopened.assets[0],origin,1),"reopened tower places across chunk boundaries")
	report.timings_ms.place=(Time.get_ticks_usec()-start)/1000.0
	var exact:=true
	for i in range(0,records.size(),4):
		var p:=Vector3i(-records[i+2],records[i+1],records[i])+origin
		var word:=records[i+3]
		var rotated: int=(word&~24)|(((((word>>3)&3)+1)%4)<<3)
		if blocks.get_cell(p)!=rotated: exact=false;break
	check(exact,"every rotated placed cell matches independent expected coordinates/material/shape")
	var placed: PackedByteArray=blocks.capture_snapshot()
	check(not blocks.place_prefab(reopened.assets[0],origin,1) and blocks.capture_snapshot()==placed,"overlapping tower rejected atomically")
	start=Time.get_ticks_usec();check(blocks.undo(),"whole-building undo accepted");report.timings_ms.undo=(Time.get_ticks_usec()-start)/1000.0
	check(blocks.capture_snapshot()==source,"whole-building undo restores exact source snapshot")
	start=Time.get_ticks_usec();check(blocks.redo(),"whole-building redo accepted");report.timings_ms.redo=(Time.get_ticks_usec()-start)/1000.0
	check(blocks.capture_snapshot()==placed,"whole-building redo restores exact placed snapshot")
	check(blocks.capture_prefab(Vector3i.ZERO,Vector3i(65,64,64))==null,"selection exceeding volume cap rejected")
	report.history=blocks.history_stats();report.failures=failures
	DirAccess.make_dir_recursive_absolute("res://reports")
	file=FileAccess.open("res://reports/prefab_building.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print(JSON.stringify(report))
	for name: String in DirAccess.get_files_at(library.directory): DirAccess.remove_absolute(library.directory.path_join(name))
	DirAccess.remove_absolute(library.directory)
	blocks.free();quit(1 if failures else 0)
