extends SceneTree

func _initialize() -> void:
	start.call_deferred()

func start() -> void:
	var viewer:=preload("res://reviews/modular_buildings/viewer.gd").new()
	root.add_child(viewer)
	if not viewer.ready_ok:
		push_error("Building review could not place its native prefabs: "+str(viewer.placement_results))
		quit(1)
	else:
		print("MODULAR_BUILDING_VIEWER_READY originals=unchanged candidates=2 review=R1")
		if "--guided-tour" in OS.get_cmdline_user_args():viewer.guided_tour()
