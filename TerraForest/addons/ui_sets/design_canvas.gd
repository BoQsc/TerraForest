# SPDX-License-Identifier: 0BSD
extends Control
## Scale a preserved 1920x1080 composition into the current window.
func _ready()->void:
	get_viewport().size_changed.connect(fit);fit()
func fit()->void:
	var available:=get_viewport_rect().size
	var factor:=minf(available.x/1920.0,available.y/1080.0)
	scale=Vector2.ONE*factor;size=Vector2(1920,1080)
	position=(available-size*factor)*0.5
