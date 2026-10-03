# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var motor: RefCounted=ClassDB.instantiate("NativePlayerMovement")
	var dt:=1.0/60.0
	check(motor.walking_velocity(Vector3(1,0,1),Vector3.ZERO,dt,false,true,false).length()<5.501,"diagonal walking cannot exceed walking speed")
	check(motor.walking_velocity(Vector3.RIGHT,Vector3.ZERO,dt,true,true,false).is_equal_approx(Vector3(9.9,0,0)),"sprint speed preserved")
	check(motor.walking_velocity(Vector3.ZERO,Vector3(5,0,5),dt,false,true,false)==Vector3.ZERO,"release stops horizontal motion immediately")
	check(motor.walking_velocity(Vector3.ZERO,Vector3.ZERO,dt,false,true,true).y==7.0,"grounded jump impulse")
	check(motor.walking_velocity(Vector3.ZERO,Vector3(0,-5,0),dt,false,false,true).y < -5.0,"holding jump in air cannot cancel gravity")
	var velocity:=Vector3.ZERO
	for i in range(60): velocity=motor.walking_velocity(Vector3.ZERO,velocity,dt,false,false,false)
	check(absf(velocity.y+20)<0.001,"one second falling accumulates gravity")
	var displacement:=Vector3.ZERO
	for i in range(60): displacement+=motor.flight_displacement(Vector3.FORWARD,0,dt,true)
	check(displacement.is_equal_approx(Vector3(0,0,-40)),"one second flight distance at 60 ticks")
	check(absf(motor.flight_displacement(Vector3.FORWARD,1,dt,false).length()-14*dt)<0.0001,"vertical plus forward flight has bounded speed")
	for invalid in [0.0,-1.0,0.5,NAN,INF]:
		check(motor.walking_velocity(Vector3.RIGHT,Vector3.ZERO,invalid,false,true,false)==Vector3.ZERO and motor.flight_displacement(Vector3.RIGHT,0,invalid,false)==Vector3.ZERO,"invalid timestep rejected: "+str(invalid))
	check(motor.walking_velocity(Vector3(NAN,0,0),Vector3.ZERO,dt,false,true,false)==Vector3.ZERO,"nonfinite input rejected")
	var swim:=Vector3.ZERO
	for i in range(120): swim=motor.swimming_velocity(Vector3.FORWARD,swim,1,3,dt,false)
	check(swim.y>0 and swim.z<0 and swim.length()<=3.001,"swim ascent and forward movement share speed cap")
	for i in range(120): swim=motor.swimming_velocity(Vector3.ZERO,swim,0,0.15,dt,false)
	check(swim.length()<0.001,"water drag stops released movement at float depth")
	check(motor.swimming_velocity(Vector3.ZERO,Vector3.ZERO,0,3,dt,false).y>0,"submerged idle player has buoyancy")
	check(motor.swimming_velocity(Vector3.ZERO,Vector3.ZERO,-1,3,dt,false).y<0,"dive overrides passive buoyancy")
	check(motor.swimming_velocity(Vector3.ZERO,Vector3.ZERO,0,NAN,dt,false)==Vector3.ZERO,"invalid water depth rejected")
	var coarse:=Vector3.ZERO
	var fine:=Vector3.ZERO
	for i in range(30): coarse=motor.swimming_velocity(Vector3.FORWARD,coarse,0,0.15,1.0/30.0,false)
	for i in range(120): fine=motor.swimming_velocity(Vector3.FORWARD,fine,0,0.15,1.0/120.0,false)
	check(coarse.distance_to(fine)<0.0001,"swim drag converges consistently across tick rates")
	quit(1 if failures else 0)
