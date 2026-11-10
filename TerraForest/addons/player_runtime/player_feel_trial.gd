# SPDX-License-Identifier: 0BSD
extends RefCounted
## Bounded presentation offsets; never changes the movement motor or aim basis.
var kick:=0.0
var pitch:=0.0
var landing:=0.0
var fov_pulse:=0.0
var fall_speed:=0.0
var was_grounded:=true
var smooth_velocity:=Vector3.ZERO
var offset:=Vector3.ZERO
var bank:=0.0
func reset()->void:
    kick=0;pitch=0;landing=0;fov_pulse=0;fall_speed=0;was_grounded=true
    smooth_velocity=Vector3.ZERO;offset=Vector3.ZERO;bank=0
func shot(aiming:bool)->void:
    var strength:=.35 if aiming else 1.0
    kick=minf(.018,kick+.008*strength)
    pitch=minf(deg_to_rad(.7),pitch+deg_to_rad(.35)*strength)
    fov_pulse=minf(.30,fov_pulse+.15*strength)
func step(delta:float,velocity:Vector3,grounded:bool,turn_rate:float,aiming:bool,allow_sway:bool=true)->Transform3D:
    var dt:=clampf(delta,0,.05)
    if not grounded:fall_speed=maxf(fall_speed,-velocity.y)
    if grounded and not was_grounded and fall_speed>1.5:
        landing=minf(.020,landing+clampf(fall_speed*.002,.004,.018))
        fov_pulse=minf(.30,fov_pulse+.12)
    if grounded:fall_speed=0
    was_grounded=grounded
    var strength:=.2 if aiming else 1.0
    smooth_velocity=smooth_velocity.lerp(velocity,1-exp(-10*dt))
    var lag:Vector3=(smooth_velocity-velocity)*.002*strength
    lag=Vector3(clampf(lag.x,-.008,.008),0,clampf(lag.z,-.006,.006))
    offset=offset.lerp(lag,1-exp(-14*dt))
    bank=lerpf(bank,clampf(-turn_rate*.008,-.012,.012)*strength,1-exp(-14*dt))
    if not allow_sway:offset=Vector3.ZERO;bank=0
    kick*=exp(-16*dt);pitch*=exp(-16*dt);landing*=exp(-13*dt);fov_pulse*=exp(-16*dt)
    return Transform3D(Basis.from_euler(Vector3(pitch,0,bank)),offset+Vector3(0,-landing,kick))
