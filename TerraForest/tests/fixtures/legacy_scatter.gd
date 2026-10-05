# SPDX-License-Identifier: 0BSD
# Frozen compatibility oracle from commit 2ad1c8a; never used by runtime.
extends RefCounted
const GRID: int = 6
const CELL_SIZE: float = 64.0
var seed: int = 1703
var density: float = 0.82
func _candidates(key: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ ((key.y * 32 + key.x + 1) * 73856093)
	var points := PackedVector3Array()
	var ids := PackedInt64Array()
	var rotations := PackedFloat32Array()
	var scales := PackedFloat32Array()
	for z in range(GRID):
		for x in range(GRID):
			var point := Vector3((key.x + (x + rng.randf_range(0.2, 0.8)) / GRID) * CELL_SIZE, 0.0, (key.y + (z + rng.randf_range(0.2, 0.8)) / GRID) * CELL_SIZE)
			var roll: float = rng.randf()
			var yaw: float = rng.randf_range(0.0, TAU)
			var scale: float = rng.randf_range(0.7, 1.18)
			# Ecological mask: grassy SW biome, tapered at the snow/sand boundaries.
			var biome: float = clampf((1000.0 - point.x) / 100.0, 0.0, 1.0) * clampf((point.z - 1000.0) / 100.0, 0.0, 1.0)
			if roll >= density * biome or point.x < 2.0 or point.z < 2.0 or point.x >= 1998.0 or point.z >= 1998.0:
				continue
			points.append(point)
			ids.append(1 + (key.y * 32 + key.x) * GRID * GRID + z * GRID + x)
			rotations.append(yaw)
			scales.append(scale)
	return {"points": points, "ids": ids, "rotations": rotations, "scales": scales}

