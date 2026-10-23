# SPDX-License-Identifier: 0BSD
extends Node3D
## Contact adapter; survival health/death is a separate gameplay requirement.
signal attacked(damage: float)
var damage_received := 0.0

func get_zombie_attack_radius() -> float:
	return 0.34

func receive_zombie_attack(damage: float) -> void:
	if not is_finite(damage) or damage <= 0.0:
		return
	damage_received += damage
	attacked.emit(damage)
