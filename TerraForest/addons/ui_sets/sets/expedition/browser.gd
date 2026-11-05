# SPDX-License-Identifier: 0BSD
extends RefCounted
static func build(host:Control)->void:
	preload("res://addons/ui_sets/editorial_browser.gd").build(host,true)
