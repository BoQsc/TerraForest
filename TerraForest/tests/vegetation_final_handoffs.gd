# SPDX-License-Identifier: 0BSD
extends "res://tests/vegetation_handoffs.gd"

func _initialize() -> void:
	seamless_suite=true
	run.call_deferred()
