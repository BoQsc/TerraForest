# SPDX-License-Identifier: 0BSD
extends Node3D

const Layouts = preload("res://addons/exploration/cave_layouts.gd")
var quests: Node
var glyph: Label3D
var remaining := 0.0
var ready_key := 0

func _ready() -> void:
	glyph=Label3D.new();glyph.text="?";glyph.font_size=256;glyph.pixel_size=.006
	glyph.modulate=Color("f5d174");glyph.outline_modulate=Color("241c0d");glyph.outline_size=24
	glyph.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	glyph.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glyph.no_depth_test=false;glyph.fixed_size=false
	add_child(glyph);hide()

static func anchor(location: Dictionary) -> Vector3:
	var point: Vector3=location.marker
	var bounds: AABB=location.bounds.grow(2.0)
	var direction:=Layouts.turn(Vector3.FORWARD,location.rotation)-Layouts.turn(Vector3.ZERO,location.rotation)
	if direction.x>0:point.x=maxf(point.x,bounds.end.x)
	elif direction.x<0:point.x=minf(point.x,bounds.position.x)
	elif direction.z>0:point.z=maxf(point.z,bounds.end.z)
	else:point.z=minf(point.z,bounds.position.z)
	return point

static func ray_matches(origin: Vector3, direction: Vector3, center: Vector3, target: Dictionary) -> bool:
	if not origin.is_finite() or not direction.is_finite() or not center.is_finite():return false
	var offset:=center-origin
	var along:=offset.dot(direction)
	if along<.05 or offset.length_squared()>9 or (offset-direction*along).length_squared()>.36:return false
	return target.is_empty() or origin.distance_squared_to(target.position)>along*along

func _process(delta: float) -> void:
	remaining-=delta
	if remaining>0:return
	remaining=.2;ready_key=0;hide()
	var game: Node=quests.game
	if game.loading_active or game.shutdown_requested:return
	var state: Dictionary=quests.store.snapshot()
	if state.phase!=1:return
	var point:=anchor(state.location)
	if point.distance_squared_to(game.player.global_position)>64*64:return
	var bounds:=AABB(point-Vector3(.5,12,.5),Vector3(1,18,1))
	if not game._actor_collision_ready(bounds):return
	var floor_hit: Dictionary=game.structures.blocks.raycast_scene(point+Vector3.UP*6,point-Vector3.UP*12,7,[game.player.get_rid()],false)
	if floor_hit.is_empty() or floor_hit.normal.y<.7:return
	global_position=floor_hit.position+Vector3.UP*1.4
	ready_key=state.key;show()

func aimed(target: Dictionary) -> bool:
	var game: Node=quests.game
	var state: Dictionary=quests.store.snapshot()
	if not visible or ready_key!=state.key or state.phase!=1 or game.loading_active or game.shutdown_requested:return false
	return ray_matches(game.camera.global_position,-game.camera.global_basis.z,global_position,target)

func try_interact(target: Dictionary) -> bool:
	if not aimed(target):return false
	var result: Dictionary=quests.resetter.begin()
	if not result.ok:quests.game._show_lake_notice(result.reason)
	return true
