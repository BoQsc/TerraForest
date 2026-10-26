# SPDX-License-Identifier: 0BSD
# Observation only: retain the production native adapter and reset/restore behavior.
extends "res://vehicle_demo/scripts/car_native.gd"
var return_events:Array=[]
func reset_vehicle()->void:
	var before:=global_transform
	var event:={"kind":"reset","physics_frame":Engine.get_physics_frames(),"before":before.origin,
		"velocity":linear_velocity,"angular":angular_velocity,"loaded":loaded_wheels,"controls":controls_enabled,
		"reset_key":Input.is_key_pressed(KEY_R),"below_world":before.origin.y< -10.0,"target":_spawn_transform.origin+Vector3.UP*.04,"stack":get_stack()}
	super.reset_vehicle()
	event["after"]=global_position;return_events.append(event);print("VEHICLE_RETURN_EVENT ",event)
func restore_parked(pose:Transform3D)->void:
	return_events.append({"kind":"restore_parked","physics_frame":Engine.get_physics_frames(),"before":global_position,"target":pose.origin})
	super.restore_parked(pose)
