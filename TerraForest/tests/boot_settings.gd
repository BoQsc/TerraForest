# SPDX-License-Identifier: 0BSD
extends SceneTree
const Policy=preload("res://addons/presentation/fullscreen_policy.gd")
func _initialize()->void:
	var path:="user://boot_settings_"+str(Time.get_ticks_usec())+".cfg"
	ProjectSettings.set_setting("terraforest/graphics_settings_path",path)
	var settings:=ConfigFile.new()
	settings.set_value("graphics","fullscreen",false)
	settings.set_value("graphics","building_lod",false)
	settings.set_value("other","sentinel","retained")
	settings.save(path)
	var failures:=0
	if Policy.migrate_boot_settings()!=OK:failures+=1
	settings.load(path)
	if settings.get_value("display","window/size/mode",-1)!=Window.MODE_WINDOWED or settings.get_value("graphics","fullscreen",true):failures+=1
	if settings.get_value("graphics","building_lod",true) or settings.get_value("other","sentinel","")!="retained":failures+=1
	var before:=FileAccess.get_file_as_bytes(path)
	Policy.migrate_boot_settings()
	if FileAccess.get_file_as_bytes(path)!=before:failures+=1
	Policy.save_fullscreen_preference(true);settings.load(path)
	if settings.get_value("display","window/size/mode",-1)!=Window.MODE_FULLSCREEN or not settings.get_value("graphics","fullscreen",false):failures+=1
	if settings.get_value("graphics","building_lod",true) or settings.get_value("other","sentinel","")!="retained":failures+=1
	DirAccess.remove_absolute(path)
	print("BOOT_SETTINGS checks=6 failures=",failures)
	quit(1 if failures else 0)
