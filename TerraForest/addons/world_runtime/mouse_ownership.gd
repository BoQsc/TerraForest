extends RefCounted

static var mode_changes:=0
static var captures:=0

static func set_mode(owner:Node,mode:int)->bool:
	if not is_instance_valid(owner) or not owner.is_inside_tree():return false
	if owner.get_viewport()!=owner.get_tree().root:return false
	if mode==Input.MOUSE_MODE_CAPTURED and owner.has_method("_mouse_capture_allowed") and not owner._mouse_capture_allowed():return false
	if Input.mouse_mode!=mode:
		Input.mouse_mode=mode
		mode_changes+=1
		if mode==Input.MOUSE_MODE_CAPTURED:captures+=1
	return true
