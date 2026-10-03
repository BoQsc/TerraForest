# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var native: RefCounted=ClassDB.instantiate("NativeVehicleAccessories")
	var original=load("res://vehicle_demo/scenes/car.tscn").instantiate()
	original.set_script(load("res://vehicle_demo/scripts/car.gd"))
	original.freeze=true;root.add_child(original);original.set_physics_process(false)
	var mounts: Array[Node3D]=[]
	for base in original._accessory_base_transforms:
		var mount:=Node3D.new();root.add_child(mount);mount.transform=base;mounts.append(mount)
	var passed: bool=native.configure(mounts,PackedFloat32Array(original._accessory_profiles))
	var max_error:=0.0
	for tick in 600:
		var dt:=1.0/120 if tick<300 else 1.0/60
		original.linear_velocity=Vector3(sin(tick*0.1)*10,cos(tick*0.04)*2,tick*0.1)
		original.angular_velocity=Vector3(0.1,sin(tick*0.05),-0.2)
		original.rotation.y=tick*0.007
		original.accessory_motion_enabled=not (tick>=200 and tick<250)
		if tick==400:
			original._reset_accessory_motion();native.reset(original.linear_velocity,original.angular_velocity)
		original._update_accessory_motion(dt)
		native.step(original.global_basis,original.linear_velocity,original.angular_velocity,dt,original.accessory_motion_enabled,original.accessory_motion_strength)
		for i in mounts.size():
			var a: Transform3D=mounts[i].transform
			var b: Transform3D=original._accessory_mounts[i].transform
			max_error=maxf(max_error,a.origin.distance_to(b.origin))
			for axis in 3: max_error=maxf(max_error,a.basis[axis].distance_to(b.basis[axis]))
	passed=passed and max_error<0.00001
	# A removed visual must not leave a dangling native pointer.
	mounts.pop_back().free()
	native.step(Basis.IDENTITY,Vector3.ZERO,Vector3.ZERO,1.0/120,true,1)
	passed=passed and not native.configure(mounts,PackedFloat32Array())
	print("ACCESSORY_PARITY ",{"passed":passed,"ticks":600,"mounts":original._accessory_mounts.size(),"max_transform_error":max_error})
	for mount in mounts: mount.free()
	original.free();quit(0 if passed else 1)
