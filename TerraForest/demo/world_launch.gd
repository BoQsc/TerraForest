# SPDX-License-Identifier: 0BSD
extends RefCounted
const PRESETS={1:"Original woodland",4:"Mountains, caves, ore veins and lakes",6:"Accessible cave entrances, ore veins and lakes"}
static func valid_slot(slot: String) -> bool:
	var pattern:=RegEx.new();pattern.compile("^[A-Za-z_][A-Za-z0-9_]{0,47}$")
	return pattern.search(slot)!=null
static func saved_slots(directory: String="user://worlds") -> PackedStringArray:
	var slots:=PackedStringArray();var folder:=DirAccess.open(directory)
	if folder==null:return slots
	for file in folder.get_files():
		if file.ends_with(".trw") and valid_slot(file.trim_suffix(".trw")):slots.append(file.trim_suffix(".trw"))
	slots.sort();return slots
static func command(slot: String,create: bool,generator: int,seed: int,gameplay: bool,directory: String="user://worlds") -> Dictionary:
	if not valid_slot(slot):return {"ok":false,"reason":"Use 1–48 letters, digits or underscores; start with a letter or underscore."}
	var canonical:=directory.path_join(slot+".trw")
	if create:
		if not PRESETS.has(generator) or seed<0 or seed>2147483647:return {"ok":false,"reason":"Choose a generator and seed between 0 and 2147483647."}
		for suffix in ["",".bak",".tmp",".regions",".models"]:
			if FileAccess.file_exists(canonical+suffix) or DirAccess.dir_exists_absolute(canonical+suffix):return {"ok":false,"reason":"That name already has world data. Choose another name or open the saved world."}
		for suffix in [".clone.lock",".prepare.lock"]:
			if FileAccess.file_exists(directory.path_join(slot+suffix)):return {"ok":false,"reason":"That world is being prepared. Choose another name."}
	elif not FileAccess.file_exists(canonical):return {"ok":false,"reason":"The selected save is no longer available. Refresh the list."}
	var args:=PackedStringArray(["--path",ProjectSettings.globalize_path("res://"),"--fullscreen","--resolution","1920x1080","--max-fps","60","res://demo/world.tscn","--","--world-slot="+slot,"--ground-cover","--actors","--vehicle-fleet","--max-fps=60"])
	if create:args.append_array(PackedStringArray(["--world-generator="+str(generator),"--world-seed="+str(seed)]))
	if gameplay:args.append("--gameplay-construction")
	return {"ok":true,"args":args}
