# SPDX-License-Identifier: 0BSD
extends "res://addons/ui_sets/themed_background.gd"
var planet:Control
var ring:Control
func _ready()->void:
	super._ready()
	ring=preload("res://demo/world_screens/kit.gd").OrbitRing.new();ring.radius=310.;ring.show_head=false
	ring.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(ring)
	planet=preload("res://demo/world_screens/planet.gd").new()
	planet.radius_px=230.;planet.tree_count=1200
	planet.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(planet)
	get_viewport().size_changed.connect(fit);fit()
func fit()->void:
	var available:=get_viewport_rect().size
	var factor:=minf(available.x/1920.,available.y/1080.)
	var center:=Vector2(available.x*0.27,available.y*0.51)
	planet.scale=Vector2.ONE*factor;planet.position=center-Vector2.ONE*planet.viewport_side()*factor*0.5
	ring.scale=Vector2.ONE*factor;ring.size=Vector2.ONE*700.;ring.position=center-ring.size*factor*0.5
func observe_progress(value:float)->void:
	ring.value=value/100.;ring.queue_redraw()
