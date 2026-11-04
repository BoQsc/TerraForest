# SPDX-License-Identifier: 0BSD
extends RefCounted

const LIBRARY=preload("res://addons/characters/runtime/assets/Zombie.sleepers.res")
var actor:CharacterBody3D
var guard:RefCounted
var phase:=""
var pose:=0
var cursor:=0.0
var clip:=""
var crawling:=false
var reversing:=false
var blocked:=false
var retry:=0.0
var wake_speed:=1.65
var envelope:=AABB()
var coverage:=AABB()
var exit_shape:CapsuleShape3D

func bounds_at(name:String,time:float)->AABB:
	var animation:=LIBRARY.get_animation(name)
	var values:PackedVector3Array=animation.get_meta("skin_envelopes")
	var index:=mini(int(floor(time*float(animation.get_meta("envelope_hz"))+.00001)),values.size()/2-1)*2
	return AABB(values[index],values[index+1])

func begin(owner_actor:CharacterBody3D,sleep_pose:int,record:PackedByteArray=PackedByteArray())->bool:
	if not phase.is_empty() or sleep_pose not in [1,2] or not owner_actor.alive or not owner_actor._r4_enabled:return false
	guard=ClassDB.instantiate("NativeZombiePosture")
	if not record.is_empty() and (not guard.validate_snapshot(record) or record.decode_u32(0)!=sleep_pose):return false
	pose=sleep_pose;phase="sleeping"
	var name:="Zombie_Sleep_Seated" if sleep_pose==1 else "Zombie_Sleep_Lying"
	if not record.is_empty() and record.decode_u32(32)!=1:
		phase="waking";crawling=record.decode_u32(36)==1;reversing=record.decode_u32(36)==2;cursor=record.decode_float(40)
		name=wake_name()
	var bounds:=bounds_at(name,cursor)
	var values:PackedVector3Array=LIBRARY.get_animation(name).get_meta("skin_envelopes")
	if phase=="sleeping":
		for index in range(2,values.size(),2):bounds=bounds.merge(AABB(values[index],values[index+1]))
	if not guard.apply_bounds(owner_actor,owner_actor.capsule,bounds):return false
	actor=owner_actor;clip=name;envelope=bounds
	coverage=bounds
	for animation_name:String in LIBRARY.get_animation_list():
		var samples:PackedVector3Array=LIBRARY.get_animation(animation_name).get_meta("skin_envelopes")
		for index in range(0,samples.size(),2):coverage=coverage.merge(AABB(samples[index],samples[index+1]))
	actor._cancel_attack();actor.cancel_traversal();actor._crawl_transition=false
	actor._manual_clip="";actor._hit_timer=0.;actor._active_action="";actor.velocity=Vector3.ZERO
	if not actor.animation_player.has_animation_library("sleepers"):actor.animation_player.add_animation_library("sleepers",LIBRARY)
	actor._play_animation(clip,true);actor.animation_player.seek(cursor,true)
	actor._set_movement_mode(phase);actor.state=phase
	return true

func wake()->void:
	if phase!="sleeping":return
	crawling=not actor._has_standing_legs();reversing=false;cursor=0.;phase="waking"
	select_wake()

func select_wake()->void:
	exit_shape=null
	clip=wake_name()
	actor._play_animation(clip,true);actor.animation_player.advance(0)
	actor._set_movement_mode("waking");actor.state="waking"

func wake_name()->String:
	return ("Zombie_Wake_Seated" if pose==1 else "Zombie_Wake_Lying")+("_Crawl" if crawling else "")

func leg_lost()->void:
	if phase=="sleeping":wake();return
	if phase=="ready" and not crawling:
		phase="waking";reversing=true
		actor._play_animation(clip,true);actor.animation_player.seek(cursor,true)
		actor._set_movement_mode("waking")

func tick(delta:float)->void:
	if not actor.alive:return
	actor.velocity.x=0.;actor.velocity.z=0.
	actor._gravity_step(delta)
	if actor.behavior_enabled:
		if phase in ["sleeping","ready"]:actor.animation_player.advance(delta)
		else:advance_wake(minf(delta,.05))
	actor.move_and_slide()

func advance_wake(delta:float)->void:
	if not crawling and not actor._has_standing_legs():reversing=true
	retry=maxf(0.,retry-delta)
	if retry>0:return
	var duration:=LIBRARY.get_animation(clip).length
	# Stay within the existing clearance sampling step at lower physics rates.
	var pose_step:=minf(delta*wake_speed,.05)
	var next:=clampf(cursor+(-pose_step if reversing else pose_step),0.,duration)
	var bounds:=bounds_at(clip,cursor).merge(bounds_at(clip,next))
	if not guard.apply_bounds(actor,actor.capsule,bounds):
		blocked=true;retry=.1;actor.state="wake_blocked";return
	blocked=false;envelope=bounds;cursor=next
	actor.animation_player.seek(cursor,true);actor.state="waking"
	if reversing and cursor<=0:
		crawling=true;reversing=false;select_wake();return
	if cursor<duration:return
	if exit_shape==null:
		exit_shape=CapsuleShape3D.new();exit_shape.radius=.24;exit_shape.height=1.2 if crawling else 1.74
	var transform:=Transform3D(Basis(Vector3.RIGHT,PI*.5) if crawling else Basis.IDENTITY,Vector3(0,.24,-.12) if crawling else Vector3(0,.87,0))
	if not guard.restore_capsule(actor,actor.capsule,exit_shape,transform):
		blocked=true;retry=.1;actor.state="wake_blocked";return
	actor._crawling=crawling;actor._crawl_transition=false;actor._crawl_shape_fraction=1. if crawling else 0.
	actor._set_movement_mode("crawling" if crawling else "standing")
	actor._play_animation("Zombie_Crawl_Idle" if crawling else "Zombie_Idle",true);actor.animation_player.advance(0)
	actor.state="wake_ready";phase="ready"

func finish()->bool:
	if phase!="ready":return false
	phase="";actor.state="crawl_idle" if crawling else "idle";return true

func snapshot()->Dictionary:
	return {"phase":phase,"pose":pose,"clip":clip,"cursor":cursor,"blocked":blocked,"reversing":reversing,"crawling":crawling,"queries":guard.statistics() if guard!=null else {}}

func capture()->PackedByteArray:
	var bytes:=PackedByteArray()
	if phase.is_empty() or not actor.alive:return bytes
	bytes.resize(16);bytes.fill(0);bytes.encode_u32(0,pose);bytes.encode_u32(4,1 if phase=="sleeping" else 3 if phase=="ready" else 2)
	bytes.encode_u32(8,1 if crawling else 2 if reversing else 0);bytes.encode_float(12,cursor)
	return bytes
