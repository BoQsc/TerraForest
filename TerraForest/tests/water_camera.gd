# SPDX-License-Identifier: 0BSD
extends SceneTree
const WaterCamera=preload("res://addons/volumetric_water/water_camera.gd")
class Water extends Node3D:
	var depth:=0.0
	func depth_at(_point: Vector3) -> float: return depth
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var camera:=Camera3D.new();root.add_child(camera)
	var water:=Water.new();root.add_child(water)
	var effect:=WaterCamera.new();root.add_child(effect)
	var original:=Environment.new();original.fog_density=0.003;camera.environment=original
	effect.configure(camera,water)
	water.depth=0.02;effect.update()
	check(not effect.underwater and camera.environment==original,"surface entry margin avoids shallow toggles")
	water.depth=1;effect.update()
	check(effect.underwater and camera.environment!=original and is_equal_approx(original.fog_density,0.003),"underwater effect leaves original environment unchanged")
	var submerged:=camera.environment
	effect.update()
	check(camera.environment==submerged,"steady immersion reuses environment resource")
	water.depth=0.01;effect.update()
	check(effect.underwater,"entry hysteresis retains effect while still submerged")
	water.depth=0;effect.update()
	check(not effect.underwater and camera.environment==original,"dry or invalidated occupancy restores exact prior environment")
	water.depth=1;effect.update();effect.free()
	check(camera.environment==original,"removing addon restores camera")
	effect=WaterCamera.new();root.add_child(effect);effect.configure(camera,water);effect.update()
	var replacement:=Environment.new();camera.environment=replacement
	effect.restore()
	check(camera.environment==replacement,"cleanup preserves another system's replacement environment")
	effect.free();water.free();camera.free()
	quit(1 if failures else 0)
