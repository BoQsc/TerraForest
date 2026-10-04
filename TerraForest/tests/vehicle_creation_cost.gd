# SPDX-License-Identifier: 0BSD
extends SceneTree
# Separate resource loading, scene allocation and synchronous _ready work.
# Headless timings exclude render uploads, pipeline compilation and presentation.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var begin:=Time.get_ticks_usec()
	var packed:=load("res://vehicle_demo/scenes/car.tscn") as PackedScene
	var load_us:=Time.get_ticks_usec()-begin
	if packed==null:
		quit(1);return
	var samples: Array=[]
	var passed:=true
	for trial in 3:
		begin=Time.get_ticks_usec()
		var car=packed.instantiate()
		var instantiate_us:=Time.get_ticks_usec()-begin
		car.freeze=true
		begin=Time.get_ticks_usec()
		root.add_child(car)
		var ready_us:=Time.get_ticks_usec()-begin
		car.set_controls_enabled(false);car.set_physics_process(false)
		passed=passed and car.driving_policy!=null and car.body_mesh_count>0
		samples.append({"trial":trial,"instantiate_us":instantiate_us,"ready_us":ready_us,"body_meshes":car.body_mesh_count})
		car.queue_free()
		await process_frame
		await process_frame
	var report: Dictionary={"passed":passed,"load_us":load_us,"samples":samples,"scope":"Headless CPU creation only; no GPU upload, compilation or first-visible-frame qualification."}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/vehicle_creation_cost.json",FileAccess.WRITE)
	if file==null:
		quit(1);return
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("VEHICLE_CREATION_COST ",JSON.stringify(report))
	quit(0 if passed else 1)
