# SPDX-License-Identifier: 0BSD
extends RefCounted
## Actual movement only: a short lead-in, followed by the ordinary stride.
const FIRST_STEP_METRES := .15
var distance := 0.0
var walking := false

func reset() -> void:
	distance = 0; walking = false

func advance(travelled: float, speed: float, allowed: bool) -> bool:
	if not allowed or not is_finite(travelled) or travelled < .001 or travelled > 2:
		reset(); return false
	distance += travelled
	var stride := (2.7 if speed > 7 else 1.8) if walking else FIRST_STEP_METRES
	if distance < stride: return false
	distance = fmod(distance, stride); walking = true
	return true
