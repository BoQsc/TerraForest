extends "res://tests/structures.gd"
func run() -> void:
	await check_scene_picking()
	print("DOOR_SCENE_RAY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
