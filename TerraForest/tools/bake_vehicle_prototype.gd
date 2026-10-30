# SPDX-License-Identifier: 0BSD
extends SceneTree
const OUTPUT:="res://vehicle_demo/assets/Vehicle.parked.res"
const RECEIPT:="res://vehicle_demo/assets/Vehicle.parked.bake.json"
const SOURCES:=["res://vehicle_demo/assets/Vehicle.glb","res://vehicle_demo/assets/Vehicle.glb.import","res://vehicle_demo/scenes/car.tscn","res://vehicle_demo/scripts/car.gd","res://vehicle_demo/scripts/car_native.gd","res://addons/vehicle_runtime/native/vehicle_prototype.cpp","res://addons/vehicle_runtime/native/vehicle_prototype.hpp","res://tools/bake_vehicle_prototype.gd"]
func _initialize()->void:run.call_deferred()
func run()->void:
	var sources:Dictionary={}
	for path:String in SOURCES:
		sources[path]=FileAccess.get_sha256(path)
		if sources[path].is_empty():push_error("Missing vehicle bake source: "+path);quit(1);return
	var engine:String=Engine.get_version_info().string
	var previous:Variant=JSON.parse_string(FileAccess.get_file_as_string(RECEIPT)) if FileAccess.file_exists(RECEIPT) else null
	if previous is Dictionary and previous.get("sources")==sources and previous.get("engine")==engine and previous.get("output_sha256")==FileAccess.get_sha256(OUTPUT):
		print("VEHICLE_PROTOTYPE_BAKE current");quit();return
	if "--check-only" in OS.get_cmdline_user_args():push_error("Parked vehicle bake is stale");quit(1);return
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var body:RigidBody3D=load("res://vehicle_demo/scenes/car.tscn").instantiate();body.freeze=true;body.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(body)
	body.set_controls_enabled(false);body.set_physics_process(false);await process_frame
	var parts:Array=[]
	for node:MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		if node.mesh!=null and node.is_visible_in_tree():parts.append({"mesh":node.mesh,"transform":body.global_transform.affine_inverse()*node.global_transform,"material":node.material_override})
	var result:Dictionary=ClassDB.instantiate("NativeVehiclePrototype").bake(parts);body.free()
	if not result.ok or result.parts.size()!=1:push_error("Ranger parked bake failed: "+str(result));quit(1);return
	var pending:=OUTPUT.trim_suffix(".res")+".pending.res"
	if ResourceSaver.save(result.parts[0].mesh,pending,ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
	if DirAccess.rename_absolute(pending,OUTPUT)!=OK:quit(1);return
	result.erase("parts")
	var receipt:Dictionary={"schema":1,"engine":engine,"sources":sources,"output_sha256":FileAccess.get_sha256(OUTPUT),"bake":result,"provenance":"Derived by original native consolidation from the supplied Vehicle.glb and existing runtime transforms/materials; retains vehicle_demo/LICENSE.txt (0BSD). No new art or external dependency."}
	var file:=FileAccess.open(RECEIPT+".pending",FileAccess.WRITE)
	if file==null:quit(1);return
	file.store_string(JSON.stringify(receipt,"  ")+"\n");file.close()
	if DirAccess.rename_absolute(RECEIPT+".pending",RECEIPT)!=OK:quit(1);return
	print("VEHICLE_PROTOTYPE_BAKE baked ",JSON.stringify(result));await process_frame;quit()
