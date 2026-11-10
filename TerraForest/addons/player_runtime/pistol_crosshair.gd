# SPDX-License-Identifier: 0BSD
extends Control
## Presentation only: center never moves away from the authoritative aim ray.
var bloom:=0.0
var hit_time:=0.0
var aiming:=false
var speed:=0.0
var baseline:CanvasItem
var owns_baseline:=false
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;hide()
func shot()->void:bloom=minf(10,bloom+5)
func confirmed_hit()->void:hit_time=.16
func update_state(delta:float,enabled:bool,ads:bool,movement:float,baseline_allowed:=true)->void:
	if enabled:
		if is_instance_valid(baseline) and not owns_baseline:
			owns_baseline=baseline.visible
			if owns_baseline:baseline.hide()
	else:
		if owns_baseline and is_instance_valid(baseline):baseline.visible=baseline_allowed
		owns_baseline=false;bloom=0;hit_time=0
	visible=enabled
	if not enabled:return
	bloom*=exp(-18*clampf(delta,0,.05));hit_time=maxf(0,hit_time-delta)
	aiming=ads;speed=movement;queue_redraw()
func _draw()->void:
	var center:=get_viewport_rect().size*.5
	var gap:=3.0 if aiming else 5.0+minf(speed,6)*.65
	gap+=bloom
	draw_circle(center,2,Color(0,0,0,.8));draw_circle(center,1,Color.WHITE)
	for axis:Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		var a:=center+axis*gap;var b:=center+axis*(gap+4)
		draw_line(a,b,Color(0,0,0,.8),4);draw_line(a,b,Color.WHITE,2)
	if hit_time>0:
		for sign_x in [-1,1]:
			for sign_y in [-1,1]:
				var axis:=Vector2(sign_x,sign_y)
				draw_line(center+axis*8,center+axis*12,Color(1,.65,.55,hit_time/.16),2)
