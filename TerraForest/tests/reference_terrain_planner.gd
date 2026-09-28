# Historical scheduling algorithm retained solely as a differential test oracle.
# Not part of the runtime scheduling path.
extends RefCounted
const FINE_SIZE := 16
var focus := Vector3.ZERO
var require_collision := true
var tiles: Dictionary = {}
var split_state: Dictionary = {}
var requested_keys: Dictionary = {}
var visible_cut: Array[Vector3i] = []
var roots: Array[Vector3i] = []

func _init() -> void:
	for z in range(0,2048,256):
		for x in range(0,2048,256): roots.append(Vector3i(x,z,256))

func requests() -> Array[Vector3i]:
	requested_keys.clear()
	var output: Array[Vector3i] = []
	for key in roots: _collect_requests(key,output)
	output.sort_custom(_priority)
	return output

func coverage() -> Dictionary:
	var keys: Array[Vector3i] = []
	var count := 0
	var ready_roots := {}
	for key in roots:
		var covered := _cover(key)
		if covered.ok:
			count+=1
			ready_roots[key]=true
			keys.append_array(covered.keys)
	return {"keys":keys,"root_coverage":count,"covered_roots":ready_roots}

func _distance(key: Vector3i) -> float:
	var dx: float = maxf(maxf(float(key.x) - focus.x, focus.x - float(key.x + key.z)), 0.0)
	var dz: float = maxf(maxf(float(key.y) - focus.z, focus.z - float(key.y + key.z)), 0.0)
	var dy: float = maxf(0.0, focus.y - 256.0) if not require_collision else 0.0
	return sqrt(dx * dx + dz * dz + dy * dy)

func _want_split(key: Vector3i) -> bool:
	if key.z <= FINE_SIZE:
		return false
	var was_split: bool = bool(split_state.get(key, false))
	var near_radius: float = 48.0 if key.z == 32 else (100.0 if key.z == 64 else float(key.z) * 1.4)
	var threshold: float = near_radius * (1.30 if was_split else 1.0)
	var answer: bool = _distance(key) < threshold
	split_state[key] = answer
	return answer

func _children(key: Vector3i) -> Array[Vector3i]:
	var half: int = key.z / 2
	return [Vector3i(key.x, key.y, half), Vector3i(key.x + half, key.y, half),
		Vector3i(key.x, key.y + half, half), Vector3i(key.x + half, key.y + half, half)]

func _collect_requests(key: Vector3i, output: Array[Vector3i]) -> void:
	if key.x >= 2000 or key.y >= 2000:
		return
	requested_keys[key] = true
	var split: bool = _want_split(key)
	# Do not rebuild unused coarse ancestors on every dig. Retain the live fine cut
	# and rebuild a dirty parent only when it will actually become visible again.
	if not tiles.has(key) or (bool(tiles[key]["dirty"]) and (not split or visible_cut.has(key))):
		output.push_back(key)
	if split:
		for child: Vector3i in _children(key):
			_collect_requests(child, output)

func _priority(a: Vector3i, b: Vector3i) -> bool:
	# Root coverage first, then near collision leaves, then intermediate caches.
	var pa: float = _distance(a) + (0.0 if a.z == 256 else (20.0 if a.z <= 32 else 200.0))
	var pb: float = _distance(b) + (0.0 if b.z == 256 else (20.0 if b.z <= 32 else 200.0))
	if a.z <= 32 and _distance(a) < 25.0:
		pa -= 5000.0
	if b.z <= 32 and _distance(b) < 25.0:
		pb -= 5000.0
	return pa < pb

func _cover(key: Vector3i) -> Dictionary:
	if key.x >= 2000 or key.y >= 2000:
		return {"ok": true, "keys": []}
	if bool(split_state.get(key, false)) and key.z > FINE_SIZE:
		var result: Array[Vector3i] = []
		var complete: bool = true
		for child: Vector3i in _children(key):
			var covered: Dictionary = _cover(child)
			if not covered["ok"]:
				complete = false
			else:
				result.append_array(covered["keys"])
		if complete:
			return {"ok": true, "keys": result}
	# A dirty live mesh remains a valid OLD visual/collision until its transaction completes.
	if tiles.has(key) and (not bool(tiles[key]["dirty"]) or visible_cut.has(key)):
		return {"ok": true, "keys": [key]}
	# Do not resurrect a stale parent when walking away during its rebuild.
	if key.z > FINE_SIZE:
		var descendants: Array[Vector3i] = []
		for child: Vector3i in _children(key):
			var part: Dictionary = _cover(child)
			if not part["ok"]:
				return {"ok": false, "keys": []}
			descendants.append_array(part["keys"])
		return {"ok": true, "keys": descendants}
	return {"ok": false, "keys": []}

