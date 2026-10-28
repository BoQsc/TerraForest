extends SceneTree

func _initialize() -> void:
	start.call_deferred()

func start() -> void:
	var comparison: bool="--comparison" in OS.get_cmdline_user_args()
	var roof: bool="--roof" in OS.get_cmdline_user_args()
	var shop_roof: bool="--shop-roof" in OS.get_cmdline_user_args()
	var large_house: bool="--large-house" in OS.get_cmdline_user_args()
	var viewer: Node3D
	if large_house:viewer=load("res://reviews/modular_buildings/large_house_viewer.gd").new()
	elif shop_roof:viewer=load("res://reviews/modular_buildings/shop_roof_viewer.gd").new()
	elif roof:viewer=load("res://reviews/modular_buildings/roof_viewer.gd").new()
	elif comparison:viewer=preload("res://reviews/modular_buildings/viewer.gd").new()
	else:viewer=load("res://reviews/modular_buildings/walkaround.tscn").instantiate()
	root.add_child(viewer)
	if not viewer.ready_ok:
		push_error("Building review could not place its native prefabs: "+str(viewer.placement_results))
		quit(1)
	else:
		if large_house:print("LARGE_HOUSE_REVIEW_READY candidate=C1 approval=approved_addition")
		elif shop_roof:print("MODULAR_SHOP_ROOF_REVIEW_READY original=B0 candidate=B2 approval=approved_default")
		elif roof:print("MODULAR_ROOF_REVIEW_READY original=A0 candidate=A2 approval=approved_default")
		else:print("MODULAR_BUILDING_VIEWER_READY" if comparison else "MODULAR_BUILDING_WALKAROUND_READY"," originals=unchanged approved_additions=1 rejected=1 review=R1")
		if comparison and "--guided-tour" in OS.get_cmdline_user_args():viewer.guided_tour()
