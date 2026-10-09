# SPDX-License-Identifier: 0BSD
extends SpotLight3D
# Engine-rendered light; no script processing or world scans.
func _init() -> void:
	name="Headlamp"
	visible=false
	spot_range=14.0
	spot_angle=38.0
	spot_attenuation=1.2
	light_energy=2.5
	light_color=Color(1.0,0.95,0.86)
	shadow_enabled=true
	position=Vector3(0.12,-0.1,-0.1)
func toggle() -> bool:
	visible=not visible
	return visible
