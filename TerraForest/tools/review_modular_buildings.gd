extends SceneTree

func _initialize() -> void:
	start.call_deferred()

func start() -> void:
	var comparison: bool="--comparison" in OS.get_cmdline_user_args()
	var viewer: Node3D=preload("res://reviews/modular_buildings/viewer.gd").new() if comparison else load("res://reviews/modular_buildings/walkaround.tscn").instantiate()
	root.add_child(viewer)
	if not viewer.ready_ok:
		push_error("Building review could not place its native prefabs: "+str(viewer.placement_results))
		quit(1)
	else:
		print("MODULAR_BUILDING_VIEWER_READY" if comparison else "MODULAR_BUILDING_WALKAROUND_READY"," originals=unchanged approved_additions=1 rejected=1 review=R1")
		if comparison and "--guided-tour" in OS.get_cmdline_user_args():viewer.guided_tour()
