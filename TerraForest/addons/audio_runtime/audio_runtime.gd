# SPDX-License-Identifier: 0BSD
extends Node3D
## Fixed playback pools; engine audio owns mixing, decoding and attenuation.
const Catalog = preload("res://addons/audio_runtime/catalog.gd")
const SPATIAL_LIMIT := 32
const BED_LIMIT := 4
const SPATIAL_LOOP_LIMIT := 8
const BUSES := ["Effects", "Ambience", "Voices", "UI"]
var catalog := Catalog.new()
var voices: Array[Dictionary] = []
var beds: Array[Dictionary] = []
var listener := Vector3.ZERO
var enabled := true
var serial := 0
var random := RandomNumberGenerator.new()
var previous: Dictionary = {}
var played := 0
var dropped := 0

func _exit_tree() -> void:
	clear()

func prepare(paths: PackedStringArray) -> bool:
	clear()
	if not catalog.prepare(paths): return false
	random.randomize()
	for title: String in BUSES:
		if AudioServer.get_bus_index("TerraForest" + title) < 0:
			AudioServer.add_bus(); var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, "TerraForest" + title); AudioServer.set_bus_send(index, "Master")
	if voices.is_empty():
		for i in SPATIAL_LIMIT:
			var node := AudioStreamPlayer3D.new(); node.name = "Voice%d" % i; add_child(node)
			node.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
			voices.append({"node": node, "handle": 0, "id": "", "priority": 0, "loop": false, "pending": false})
		for i in BED_LIMIT:
			var node := AudioStreamPlayer.new(); node.name = "Bed%d" % i; add_child(node)
			node.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
			beds.append({"node": node, "handle": 0, "id": "", "priority": 0, "loop": true, "pending": false})
	return true

func emit_event(event: String, context: Dictionary = {}) -> int:
	var point: Variant = context.get("position", listener)
	if not enabled or not point is Vector3 or not point.is_finite(): return 0
	var row := catalog.resolve(event, context)
	if row.is_empty() or row.loop: return 0
	return _play(row, point, false)

func start_loop(event: String, context: Dictionary = {}, background: bool = false) -> int:
	var point: Variant = context.get("position", listener)
	if not enabled or not point is Vector3 or not point.is_finite(): return 0
	var row := catalog.resolve(event, context)
	if row.is_empty() or not row.loop: return 0
	return _play(row, point, background)

func _play(row: Dictionary, point: Vector3, background: bool) -> int:
	if not background and listener.distance_squared_to(point) > row.range * row.range: dropped += 1; return 0
	var pool: Array[Dictionary] = beds if background else voices
	var active := 0
	var looping := 0
	for entry in voices + beds:
		if (entry.node.playing or entry.pending) and entry.id == row.id: active += 1
	for entry in voices:
		if entry.node.playing and entry.loop: looping += 1
	if row.loop and not background and looping >= SPATIAL_LOOP_LIMIT: dropped += 1; return 0
	var slot: Dictionary = {}
	var victim: Dictionary = {}
	for entry in pool:
		if not entry.node.playing and not entry.pending:
			if slot.is_empty(): slot = entry
			continue
		if not entry.loop and entry.priority < row.priority and (victim.is_empty() or entry.priority < victim.priority): victim = entry
	if active >= row.limit: dropped += 1; return 0
	if slot.is_empty(): slot = victim
	if slot.is_empty(): dropped += 1; return 0
	var index := random.randi_range(0, row.files.size() - 1)
	if row.files.size() > 1 and index == previous.get(row.id, -1): index = (index + random.randi_range(1, row.files.size() - 1)) % row.files.size()
	previous[row.id] = index
	var node: Node = slot.node
	node.stop(); node.stream = catalog.streams[row.files[index]]
	node.bus = "TerraForest" + row.bus; node.volume_db = row.gain_db
	node.pitch_scale = random.randf_range(1.0 / row.pitch, row.pitch)
	if not background: node.global_position = point; node.max_distance = row.range; node.unit_size = maxf(2.0, row.range * .9)
	serial += 1; slot.handle = serial; slot.id = row.id; slot.priority = row.priority; slot.loop = row.loop
	# A cancellable deferred start avoids starting/stopping a background playback
	# inside the same admission burst. Pending beds still occupy their fixed slot.
	slot.pending = background
	if background: _start_bed.call_deferred(serial)
	else: node.play()
	played += 1
	return serial

func _start_bed(handle: int) -> void:
	if not enabled: return
	for slot in beds:
		if slot.handle == handle and slot.pending:
			slot.pending = false; slot.node.play(); return

func update_loop(handle: int, point: Vector3, gain_db: float = 0.0) -> bool:
	if not point.is_finite() or not Catalog.number(gain_db, -60, 0): return false
	for slot in voices + beds:
		if slot.handle != handle or not slot.loop or (not slot.node.playing and not slot.pending): continue
		if slot.node is AudioStreamPlayer3D:
			slot.node.global_position = point
			if listener.distance_squared_to(point) > slot.node.max_distance * slot.node.max_distance: stop(handle); return false
		var row: Dictionary = catalog.sounds[slot.id]
		slot.node.volume_db = row.gain_db + gain_db
		return true
	return false

func stop(handle: int) -> bool:
	if handle <= 0: return false
	for slot in voices + beds:
		if slot.handle == handle:
			slot.node.stop(); slot.node.stream = null; slot.handle = 0; slot.pending = false; return true
	return false

func clear() -> void:
	for slot in voices + beds:
		slot.node.stop(); slot.node.stream = null; slot.handle = 0; slot.pending = false
	previous.clear()

func set_enabled(value: bool) -> void:
	enabled = value
	if not value: clear()

func set_volume(bus: String, value: float) -> void:
	if bus not in BUSES or not Catalog.number(value, 0, 1): return
	var index := AudioServer.get_bus_index("TerraForest" + bus)
	if index >= 0:
		AudioServer.set_bus_mute(index, value == 0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(.0001, value)))

func statistics() -> Dictionary:
	var active := 0
	for slot in voices + beds:
		if slot.node.playing or slot.pending: active += 1
	return {"active": active, "spatial_capacity": voices.size(), "bed_capacity": beds.size(), "played": played, "dropped": dropped, "resident_bytes": catalog.resident_bytes, "packs": catalog.packs.duplicate()}
