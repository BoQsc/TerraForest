# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.physics_ticks_per_second=120
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var scene=load("res://vehicle_demo/scenes/car.tscn")
	# Ballistic chassis test: isolate actual physics geometry/CCD from driving,
	# wheel forces, terrain loading and visual deformation. No rendered-FPS claim.
	for kind in ["thin_wall","trunk"]:
		for speed in [30.0,60.0,100.0]:
			var obstacle=ClassDB.instantiate("NativeStaticBatch")
			var size:=Vector3(12,8,.1) if kind=="thin_wall" else Vector3(.7,8,.7)
			var configured: bool=obstacle.configure_asset("tests/impact",BoxMesh.new()) and obstacle.configure_collision_only() and obstacle.configure_collision(AABB(Vector3(-size.x/2,0,-size.z/2),size),32,8,2)
			root.add_child(obstacle)
			var transforms: Array[Transform3D]=[Transform3D.IDENTITY]
			configured=configured and obstacle.upsert_transforms(PackedInt64Array([1]),transforms)
			obstacle.set_collision_focus(Vector3.ZERO)
			for tick in 4: await physics_frame
			var car=scene.instantiate();car.position=Vector3(0,2,-8)
			root.add_child(car);car.set_physics_process(false);car.set_process(false)
			car.gravity_scale=0;car.collision_layer=4;car.collision_mask=2
			car.linear_velocity=Vector3(0,0,speed)
			var max_z: float=car.position.z
			var peak_contacts:=0
			for tick in 40:
				await physics_frame
				max_z=maxf(max_z,car.position.z)
				peak_contacts=maxi(peak_contacts,car.get_contact_count())
			var passed: bool=configured and car.continuous_cd and car.position.is_finite() and max_z<0 and peak_contacts>0 and car.linear_velocity.z<speed*.5
			print("VEHICLE_HIGH_SPEED_COLLISION ",{"passed":passed,"obstacle":kind,"speed_mps":speed,"speed_kph":speed*3.6,"max_center_z":max_z,"final_velocity":car.linear_velocity,"peak_contacts":peak_contacts,"physics_hz":120,"ticks":40})
			if not passed: failures+=1
			car.free();obstacle.free()
	print("VEHICLE_HIGH_SPEED_RESULT failures=",failures," cases=6 scope=ballistic_chassis_native_static_proxies")
	quit(0 if failures==0 else 1)
