# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var library:=preload("res://addons/structures/prefab_library.gd").new()
	library.directory="user://tests/tower_connectivity_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	var module: Resource=load("res://addons/structures/prefabs/tower_floor.tres")
	var result: Dictionary=library.stack(module,4,"Connected floors")
	check(result.ok and result.asset.get_meta("stack_height")==16,"four-storey assembly preserves explicit module pitch")
	var blocks: Node3D=ClassDB.instantiate("NativeBlockWorld")
	check(blocks.place_prefab(result.asset,Vector3i.ZERO,0),"assembled cells place without overlaps")
	var clearance:=true;var levels:=true
	for floor_index in 3:
		for step in 16:
			var z:=step*0.25+0.125
			var foot:=floor_index*4+1+(step+1)*0.25
			for x: float in [-0.5,0.5,1.5]:
				var floor_hit: Dictionary=blocks.raycast_cells(Vector3(x,foot+0.02,z),Vector3(x,foot-0.1,z))
				levels=levels and not floor_hit.is_empty() and absf(floor_hit.position.y-foot)<0.001
				var ceiling: Dictionary=blocks.raycast_cells(Vector3(x,foot+0.02,z),Vector3(x,foot+1.85,z))
				clearance=clearance and ceiling.is_empty()
		var landing: Dictionary=blocks.raycast_cells(Vector3(0.5,floor_index*4+5.1,4.5),Vector3(0.5,floor_index*4+4.9,4.5))
		levels=levels and not landing.is_empty() and absf(landing.position.y-(floor_index*4+5))<0.001
	check(levels,"every quarter step reaches the next floor landing without a height gap")
	check(clearance,"three stacked flights retain 1.85 metres of vertical headroom across their width")
	var reopened: Resource=ResourceLoader.load(result.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.get_meta("stack_height")==16,"explicit assembly spacing survives asset reload")
	module=module.duplicate();module.set_meta("stack_height",0)
	check(not library.stack(module,2,"Invalid pitch").ok,"invalid authored spacing is rejected")
	DirAccess.remove_absolute(result.path);DirAccess.remove_absolute(library.directory)
	blocks.free()
	quit(1 if failures else 0)
