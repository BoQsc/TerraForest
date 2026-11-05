# SPDX-License-Identifier: 0BSD
extends SceneTree
## Temporary probe: elevation distribution of the mockup's planet noise.

func _initialize() -> void:
	var mockup: Control = load("res://demo/world_loading_diorama.gd").new()
	mockup.noise_land = mockup.make_noise(8841229, 1.15, 5, 0.52)
	mockup.noise_warp = mockup.make_noise(8841229 + 7717, 0.72, 2, 0.5)
	mockup.noise_detail = mockup.make_noise(8841229 + 19283, 2.9, 4, 0.55)
	var values: Array[float] = []
	var golden := PI * (3.0 - sqrt(5.0))
	for i in 6000:
		var y := 1.0 - 2.0 * (float(i) + 0.5) / 6000.0
		var radius := sqrt(maxf(0.0, 1.0 - y * y))
		var theta := golden * float(i)
		values.append(mockup.elevation(Vector3(cos(theta) * radius, y, sin(theta) * radius)))
	values.sort()
	var total := float(values.size())
	print("min %.4f max %.4f" % [values[0], values[-1]])
	for q in [0.1, 0.25, 0.4, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.9, 0.95]:
		print("p%02d %%: %.4f" % [int(q * 100.0), values[int(q * total)]])
	for level in [-0.05, -0.02, -0.01, 0.0, 0.02, 0.05]:
		var land := 0
		for value in values:
			if value > level:
				land += 1
		print("land above %.3f: %.1f%%" % [level, 100.0 * float(land) / total])
	mockup.free()
	quit()
