# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene=load("res://vehicle_demo/scenes/car.tscn")
	var cars: Array[Node]=[]
	for i in 2:
		var car=scene.instantiate();car.position=Vector3(i*10,10,0)
		root.add_child(car);car.freeze=true;car.set_physics_process(false);cars.append(car)
	var before: int=cars[0].find_children("*","Node",true,false).size()
	await process_frame;await process_frame
	var after: int=cars[0].find_children("*","Node",true,false).size()
	var passed:=not cars[0].has_node("VehicleVisual/Model") and not cars[1].has_node("VehicleVisual/Model") and after<before
	var shared:=0
	for node in cars[0].find_children("*","MeshInstance3D",true,false):
		var peer=cars[1].get_node(cars[0].get_path_to(node))
		passed=passed and node.mesh!=null and node.mesh==peer.mesh
		shared+=1
	passed=passed and shared==32 and cars[0]._accessory_mounts.size()==11 and cars[0]._damage_visuals.size()==10
	# A per-instance replacement must not change the peer's shared source mesh.
	var visual: MeshInstance3D=cars[0]._damage_visuals[0]
	var original: Mesh=visual.mesh
	visual.mesh=original.duplicate();cars[0].repair_visual_damage()
	passed=passed and visual.mesh==original
	print("VEHICLE_VISUAL_SHARING ",{"passed":passed,"nodes_before":before,"nodes_after":after,"shared_mesh_instances":shared,"accessories":cars[0]._accessory_mounts.size(),"damage_meshes":cars[0]._damage_visuals.size()})
	for car in cars: car.free()
	quit(0 if passed else 1)
