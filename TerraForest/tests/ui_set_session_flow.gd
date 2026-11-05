# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	super._initialize()
