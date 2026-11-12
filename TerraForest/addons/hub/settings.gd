# SPDX-License-Identifier: 0BSD
extends RefCounted
## Hub preferences in user://hub/settings.json. The tray icon is experimental,
## so it is OFF unless a player opts in.
const PATH:="user://hub/settings.json"
const DEFAULTS:={"tray_enabled":false}
static func read()->Dictionary:
	var out:=DEFAULTS.duplicate()
	if not FileAccess.file_exists(PATH):return out
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		for key:Variant in parsed:
			if DEFAULTS.has(key):out[key]=parsed[key]
	return out
static func write(values:Dictionary)->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATH.get_base_dir()))
	var file:=FileAccess.open(PATH,FileAccess.WRITE)
	if file==null:return
	file.store_string(JSON.stringify(values,"\t"))
	file.close()
static func tray_enabled()->bool:
	return bool(read().get("tray_enabled",false))
static func set_tray_enabled(value:bool)->void:
	var values:=read()
	values["tray_enabled"]=value
	write(values)
