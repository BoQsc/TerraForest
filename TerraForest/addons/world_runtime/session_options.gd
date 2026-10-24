# SPDX-License-Identifier: 0BSD
extends RefCounted
# Immutable for the lifetime of a world/worker; reset only after its teardown.
const KEY="terraforest/session_arguments"
const OFFSCREEN="terraforest/offscreen_session"
static func arguments()->PackedStringArray:
	return ProjectSettings.get_setting(KEY,OS.get_cmdline_user_args())
static func set_arguments(value:PackedStringArray,offscreen:bool=false)->void:
	ProjectSettings.set_setting(KEY,value.duplicate());ProjectSettings.set_setting(OFFSCREEN,offscreen)
static func reset()->void:
	ProjectSettings.set_setting(KEY,null);ProjectSettings.set_setting(OFFSCREEN,null)
static func user_arguments(command:PackedStringArray)->PackedStringArray:
	var separator:=command.find("--")
	return command.slice(separator+1) if separator>=0 else PackedStringArray()
