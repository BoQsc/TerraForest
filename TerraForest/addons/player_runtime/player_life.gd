# SPDX-License-Identifier: 0BSD
extends RefCounted
const Spawn=preload("res://addons/world_runtime/introduction_spawn.gd")
var game:Node
var state:RefCounted
var dead:=false
var anchored:=false
var delay:=0.0
var returning:=false
var searching:=false
var candidate:=0
var surface_retry:=false
var blocked:=false

func prepare(owner_game:Node)->bool:
	game=owner_game;state=ClassDB.instantiate("NativePlayerLife")
	return game.persistence.register_component("player_life",state.capture_storage_snapshot,restore,state,PackedByteArray())

func restore(data:PackedByteArray)->bool:
	if not state.restore_storage_snapshot(data):return false
	var saved:Dictionary=state.snapshot();dead=saved.dead;anchored=saved.has_spawn
	delay=0.;returning=false;searching=false;candidate=0;surface_retry=false;blocked=false
	return true

func set_spawn(point:Vector3,heading:float)->bool:
	if not state.set_spawn(point,wrapf(heading,-PI,PI)):return false
	anchored=true;blocked=false;return true

func damage(amount:float)->void:
	if dead or game.loading_active or game.shutdown_requested or not game.terrain.world_ready or game.session_menu.developer or game.session_menu.pauses_world() or game.player_view.entry.pending or game.player_view.entry.active:return
	if not state.damage(amount):return
	game.terrain.changed_since_save=true
	dead=state.snapshot().dead
	if not dead:
		game._show_lake_notice("Hit · %.0f health remaining"%state.snapshot().health);return
	game._clear_motion();game.tool_view.cancel_attack();game.terrain_placement.held=false
	game._show_lake_notice("You were defeated · returning to your starting shelter")

func step(delta:float)->void:
	if game.shutdown_requested or game.loading_active or game.waiting_spawn or game.needs_floor_spawn or not game.terrain.world_ready or game.terrain.pending_edit:return
	if not anchored and not game.world_vehicle.driving and not game.fly and clear(game.player.position):set_spawn(game.player.position,game.yaw)
	if not dead or blocked or not game.app_focused or game.session_menu.pauses_world() or game.player_hud.inventory_open:return
	game._clear_motion()
	if not anchored:
		game._show_lake_notice("Respawn unavailable · no safe starting point saved");blocked=true;return
	if not returning:
		delay+=minf(delta,.1)
		if delay<2.:return
		game.world_vehicle.release_for_respawn(game)
		game.player_view.entry.finish();game.player_view.entry.pending=false
		game.fly=false
		var saved:Dictionary=state.snapshot()
		game.teleport(saved.spawn,saved.spawn.y)
		returning=true;return
	if not searching:
		searching=true;candidate=0
	for attempt in 2:
		var center:Vector3=game.player.position if surface_retry else state.snapshot().spawn
		var point:=center
		if candidate>0:
			var angle:float=(candidate-1)%8*TAU/8.
			var radius:float=2.+floorf((candidate-1)/8.)*2.
			point+=Vector3(cos(angle)*radius,0,sin(angle)*radius)
			var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP*3,7,[game.player.get_rid()]))
			point=hit.position+Vector3.UP*.03 if not hit.is_empty() else Vector3.INF
		candidate+=1
		if point.is_finite() and clear(point):
			game.player.position=point;game.player.velocity=Vector3.ZERO
			game.yaw=state.snapshot().yaw;game.pitch=0.;game.player.rotation=Vector3(0,game.yaw,0);game.camera.rotation=Vector3.ZERO
			if not state.respawn():return
			dead=false;delay=0.;returning=false;searching=false;surface_retry=false
			game.zombie_target.damage_received=0.;game.player_view.entry.arm_respawn()
			game.terrain.changed_since_save=true;game._show_lake_notice("Awake again · your belongings are safe");return
		if candidate>48:
			if not surface_retry:
				surface_retry=true;searching=false;game.teleport(state.snapshot().spawn);return
			blocked=true;game._show_lake_notice("Respawn blocked · clear the starting area in developer mode");return

func clear(point:Vector3)->bool:
	if not game.world_vehicle.ready_bounds(game,AABB(point-Vector3(.4,.1,.4),Vector3(.8,2,.8))) or game.lakes.depth_at(point)>0 or not Spawn.clear(game,point):return false
	var space:PhysicsDirectSpaceState3D=game.get_world_3d().direct_space_state
	for offset:Vector3 in [Vector3(.28,0,0),Vector3(-.28,0,0),Vector3(0,0,.28),Vector3(0,0,-.28)]:
		var feet:Vector3=point+offset
		var hit:Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(feet+Vector3.UP*.15,feet-Vector3.UP*.15,7,[game.player.get_rid()]))
		if hit.is_empty() or hit.normal.y<.85:return false
	var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.9);query.collision_mask=8|(1<<16)|(1<<18);query.exclude=[game.player.get_rid()]
	return space.intersect_shape(query,1).is_empty()
