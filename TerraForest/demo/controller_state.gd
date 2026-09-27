# SPDX-License-Identifier: 0BSD
# Current key state only. No movement queue, integration history, easing or inertia.
extends RefCounted
var held: Dictionary = {}
var last_event_us: int = 0
var last_press_us: int = 0
var last_release_us: int = 0
var release_pending: bool = false

func set_key(code: int, down: bool, at_us: int) -> void:
	if code not in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_CTRL, KEY_SHIFT]:
		return
	var had_motion: bool = direction() != Vector3.ZERO
	if down:
		held[code] = true
		last_press_us = at_us
	else:
		held.erase(code)
	last_event_us = at_us
	if had_motion and direction() == Vector3.ZERO:
		last_release_us = at_us
		release_pending = true

func direction() -> Vector3:
	return Vector3(float(held.has(KEY_D))-float(held.has(KEY_A)), 0.0,
		float(held.has(KEY_S))-float(held.has(KEY_W))).normalized()

func vertical() -> float:
	return float(held.has(KEY_SPACE))-float(held.has(KEY_CTRL))

func sprint() -> bool:
	return held.has(KEY_SHIFT)

func clear(at_us: int) -> void:
	if not held.is_empty():
		last_release_us = at_us
		release_pending = true
	held.clear()
	last_event_us = at_us
