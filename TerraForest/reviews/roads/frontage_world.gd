extends "res://demo/world.gd"
var review_input_active:=false
func _mouse_capture_allowed()->bool:
	return review_input_active and super._mouse_capture_allowed()
