extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var car=load("res://vehicle_demo/scenes/car.tscn").instantiate();root.add_child(car);car.freeze=true;car.set_physics_process(false)
 var parts:=0
 for node in car.find_children("*","MeshInstance3D",true,false):
  if node.mesh!=null and node.is_visible_in_tree():parts+=1
 print("PACKAGE_VEHICLE_PARTS ",parts)
 var fleet=ClassDB.instantiate("NativeVehicleFleet")
 var identity=fleet.spawn(Transform3D(Basis.IDENTITY,Vector3(800,50,800)))
 car.free();await process_frame
 quit(0 if parts==32 and identity>0 else 1)
