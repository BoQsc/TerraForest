# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var catalog=load("res://addons/structures/expansion_catalog.gd")
	var assets:Array=catalog.assets()
	check(assets.size()==9,"nine E2 candidates load from game resources")
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(blocks);blocks.set_process(false)
	var empty:PackedByteArray=blocks.capture_snapshot()
	for asset:Resource in assets:
		var valid:bool=asset.get_meta("expansion_revision","")=="E2" and asset.get_meta("review_only",false) and not asset.has_meta("approved_revision") and not asset.has_meta("approved_for_default")
		var records:PackedInt32Array=asset.get_records()
		for offset in range(0,records.size(),4):
			var decoded:Dictionary=blocks.decode_block(records[offset+3]);valid=valid and not decoded.is_empty() and decoded.appearance>=0
		check(valid,asset.resource_name+" retains review identity and valid independent cells")
		blocks.restore_snapshot(empty);check(blocks.set_cells(records),"published "+asset.resource_name)
		blocks.flush_bakes();check(blocks.stats().appearance_layers==8,"shared eight-layer material loads in PCK")
		var collision_mesh_valid:=true
		for child in blocks.get_children():
			if child is MeshInstance3D:
				var arrays:Array=child.mesh.surface_get_arrays(0)
				var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
				for i in range(0,indices.size(),3):
					var a:=vertices[indices[i]];var b:=vertices[indices[i+1]];var c:=vertices[indices[i+2]]
					collision_mesh_valid=collision_mesh_valid and (b-a).cross(c-a).length_squared()>=1e-12
		check(collision_mesh_valid,asset.resource_name+" joined surfaces contain no collision slivers")
		if asset.get_meta("expansion_id")=="warehouse_w1":
			var roofing:=true
			for offset in range(0,records.size(),4):
				var decoded:Dictionary=blocks.decode_block(records[offset+3])
				if decoded.shape in [4,12,13,14,15,16,17,18] or decoded.shape>=32:roofing=roofing and decoded.appearance==5
			check(roofing,"warehouse roof and gables consistently use zinc")
		if asset.get_meta("expansion_id")=="town_hall_t1":
			var samples:=PackedVector3Array()
			for y:float in [.02,.08,.11]:
				for z:float in [.02,.1,.5,.9,.98]:samples.append_array(PackedVector3Array([Vector3(1.5,14+y,20+z),Vector3(1.9999,14+y,20+z)]))
			var filled:PackedByteArray=blocks.sample_solid(samples);var continuous:=filled.count(1)>8
			for i in range(0,filled.size(),2):continuous=continuous and filled[i]==filled[i+1]
			check(continuous,"actual hall coping runs along its uncut axis without per-cell notches")
			check(blocks.decode_block(blocks.get_cell(Vector3i(0,14,10))).shape==30 and blocks.decode_block(blocks.get_cell(Vector3i(24,14,10))).shape==30,"both side parapets retain their independently addressable caps")
	var icons=load("res://addons/player_runtime/shape_icons.gd")
	var orientations=load("res://addons/player_runtime/shape_orientations.gd")
	var assemblies=load("res://addons/player_runtime/building_assemblies.gd")
	check(icons!=null and orientations!=null and assemblies!=null,"baked construction helper scripts are exported")
	for path:String in ["res://addons/player_runtime/art/shape_icons.trtex","res://addons/player_runtime/art/building_assemblies.trtex","res://addons/player_runtime/art/shape_orientations/shape_36.trtex"]:
		var pixels:=Image.new();check(pixels.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK and not pixels.is_empty(),"packed baked image "+path)
	var notices:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/credits/notices.json"))
	check(notices.notices.any(func(entry:Dictionary):return entry.id=="building_expansion" and entry.text.contains("CC0-1.0")),"asset-specific CC0 notice is present in offline credits")
	blocks.free();print("BUILDING_EXPANSION_PACK checks=",checks," failures=",failures);quit(1 if failures else 0)
