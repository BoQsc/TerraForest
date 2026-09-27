# SPDX-License-Identifier: 0BSD
# A bounded capture buffer, not an unbounded history replayed by the renderer.
# Adjacent collinear sphere samples are swept; corners and operation order stay.
extends RefCounted
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
const LIMIT: int = 4
var samples: Array[Dictionary] = []
var coalesced: int = 0
var backpressure: int = 0

func clear() -> void:
	samples.clear()

func cancel_continuous() -> void:
	# Releasing the brush must not drain seconds of unsubmitted held strokes.
	# A deliberate click/cube already captured remains ordered until submitted.
	for i in range(samples.size() - 1, -1, -1):
		if bool(samples[i].get("continuous", false)):
			samples.remove_at(i)

func push_cube(cell: Vector3i, material: int) -> bool:
	var key: Dictionary = {"cube": true, "cell": cell, "material": material}
	if not samples.is_empty() and bool(samples.back()["cube"]) and samples.back()["cell"] == cell and int(samples.back()["material"]) == material:
		coalesced += 1
		return true
	if samples.size() >= LIMIT:
		backpressure += 1
		return false
	key["captured_us"] = Time.get_ticks_usec()
	samples.push_back(key)
	return true

func push_sweep(a: Vector3, b: Vector3, radius: float, shape: int, add: bool, material: int, continuous: bool) -> bool:
	var next: Dictionary = {"cube": false, "a": a, "b": b, "radius": radius,
		"shape": shape, "add": add, "material": material, "continuous": continuous}
	if not samples.is_empty():
		var last: Dictionary = samples.back()
		if not bool(last["cube"]) and last["shape"] == shape and last["add"] == add and last["material"] == material and is_equal_approx(float(last["radius"]), radius):
			var start: Vector3 = last["a"]
			var end: Vector3 = last["b"]
			if end.distance_to(b) < 0.015:
				coalesced += 1
				return true
			var span: Vector3 = b - start
			var t: float = clampf((end - start).dot(span) / maxf(span.length_squared(), 0.000001), 0.0, 1.0)
			var deviation: float = end.distance_to(start + span * t)
			# Never replace an L-shaped stroke by a diagonal destructive shortcut.
			if shape == 0 and end.distance_to(a) < 0.02 and span.length() <= minf(16.0, radius * 4.0) and deviation <= 0.04:
				last["b"] = b
				last["continuous"] = bool(last["continuous"]) and continuous
				coalesced += 1
				return true
	if samples.size() >= LIMIT:
		backpressure += 1
		return false
	next["captured_us"] = Time.get_ticks_usec()
	samples.push_back(next)
	return true

func pop() -> Dictionary:
	if samples.is_empty():
		return {}
	var sample: Dictionary = samples.pop_front()
	if bool(sample["cube"]):
		var cell: Vector3i = sample["cell"]
		return {"command": Codec.command(3, [cell.x, cell.y, cell.z, sample["material"]]),
			"lo": Vector3(cell) - Vector3.ONE * 2.0, "hi": Vector3(cell) + Vector3.ONE * 3.0, "sample": sample}
	var a: Vector3 = sample["a"]
	var b: Vector3 = sample["b"]
	var radius: float = sample["radius"]
	var margin: Vector3 = Vector3.ONE * (radius + 5.0)
	return {"command": Codec.brush(a, b, radius, int(sample["shape"]), bool(sample["add"]), int(sample["material"])),
		"lo": a.min(b) - margin, "hi": a.max(b) + margin, "sample": sample}

# Nearby pending samples may share ONE rebuild, but all native commands are
# applied in original order. No waiting to fill a batch, no dropped corners.
func pop_batch() -> Array[Dictionary]:
	var group: Array[Dictionary] = []
	if samples.is_empty():
		return group
	var first: Dictionary = samples.front()
	group.push_back(pop())
	if bool(first["cube"]) or int(first["shape"]) != 0 or float(first["radius"]) > 4.0:
		return group
	var low: Vector3 = first["a"].min(first["b"])
	var high: Vector3 = first["a"].max(first["b"])
	while group.size() < LIMIT and not samples.is_empty():
		var next: Dictionary = samples.front()
		if bool(next["cube"]) or int(next["shape"]) != int(first["shape"]) or bool(next["add"]) != bool(first["add"]) or int(next["material"]) != int(first["material"]) or not is_equal_approx(float(next["radius"]), float(first["radius"])):
			break
		var next_low: Vector3 = low.min(next["a"]).min(next["b"])
		var next_high: Vector3 = high.max(next["a"]).max(next["b"])
		var span: Vector3 = next_high - next_low
		if maxf(span.x, maxf(span.y, span.z)) > 8.0:
			break
		low = next_low
		high = next_high
		group.push_back(pop())
	return group
