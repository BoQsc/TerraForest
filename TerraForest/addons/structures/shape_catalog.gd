extends RefCounted

const NAMES: Array[String] = ["Cube", "Slab", "Stairs", "Slope", "Post", "Sphere", "Round column", "Top plate", "Thin panel", "Frame corner", "Quarter arch", "Roof ridge", "Outer roof corner", "Inner roof corner"]
const MOUNTS: Array[String] = ["Upright", "Tip forward", "Upside down", "Tip backward", "Roll left", "Roll right"]

static func rotation_count(shape_id: int) -> int:
	return 24 if shape_id > 8 else 4

static func rotation_name(orientation: int) -> String:
	return "%s · %d°" % [MOUNTS[orientation / 4], (orientation % 4) * 90]

static func turn(shape_id: int, orientation: int, tilt: bool = false) -> int:
	if shape_id <= 8:
		return (orientation + 1) % 4
	if tilt:
		return ((orientation / 4 + 1) % 6) * 4 + orientation % 4
	return (orientation / 4) * 4 + (orientation + 1) % 4
