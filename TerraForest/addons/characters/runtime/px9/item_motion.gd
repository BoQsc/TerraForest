# SPDX-License-Identifier: CC0-1.0
# One authoritative clock samples human and item clips together.
# Events are signals; the owning game decides effects, ammunition and damage.
extends Node

signal action_started(action_id: String)
signal action_finished(action_id: String)
signal action_cancelled(action_id: String)
signal action_looped(action_id: String, cycle: int)
signal event_reached(event_name: String, details: Dictionary)
signal pose_sampled(action_id: String, seconds: float, frame: float)

const Definition = preload("item_definition.gd")
const EPSILON := 0.00000001

var auto_process := true
var auto_return := true
var speed := 1.0
var repeat_override: Variant = null
var definition: Dictionary = {}
var actions: Dictionary = {}
var human_player: AnimationPlayer
var item_player: AnimationPlayer
var current_action := ""
var time_seconds := 0.0
var playing := false
var active := false
var cycle := 0

var _human_names := {}
var _item_names := {}
var _generation := 0
var _clip: Dictionary = {}
var _blend_duration := 0.0
var _blend_elapsed := 0.0
var _blend_poses: Array = []

func _ready() -> void:
	# A host with its own animation schedule can disable auto_process and call
	# advance() after its locomotion pose. The FP library contains no leg tracks.
	process_priority = 20

func configure(human: AnimationPlayer, item: AnimationPlayer, data: Dictionary) -> Error:
	var problems := Definition.validate(data)
	if not problems.is_empty() or human == null:
		push_error("Cannot configure item motion: " + "; ".join(problems))
		return ERR_INVALID_DATA
	var human_names := {}
	var item_names := {}
	for action: Dictionary in data["actions"]:
		var id := String(action["id"])
		var human_name := find_animation(human, String(action["human_clip"]))
		var requested_item := String(action.get("item_clip", ""))
		var item_name := find_animation(item, requested_item) if item != null and not requested_item.is_empty() else ""
		if human_name.is_empty() or (not requested_item.is_empty() and item_name.is_empty()):
			push_error("Missing paired animations for " + id)
			return ERR_DOES_NOT_EXIST
		var duration := float(action["frame_end"]) / float(data["fps"])
		if absf(human.get_animation(human_name).length - duration) > 0.00002 or (not item_name.is_empty() and absf(item.get_animation(item_name).length - duration) > 0.00002):
			push_error("Paired clip duration differs from definition: " + id)
			return ERR_INVALID_DATA
		human_names[id] = human_name
		item_names[id] = item_name
	cancel()
	human_player = human
	item_player = item
	definition = data.duplicate(true)
	actions = Definition.action_map(definition)
	_human_names = human_names
	_item_names = item_names
	current_action = ""
	_clip = {}
	time_seconds = 0.0
	cycle = 0
	human_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if item_player != null:
		item_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return OK

func play_action(action_id: String, blend_seconds: float = 0.0) -> Error:
	if not actions.has(action_id):
		return ERR_DOES_NOT_EXIST
	if not is_finite(blend_seconds) or blend_seconds < 0.0:
		return ERR_INVALID_PARAMETER
	if active and not current_action.is_empty():
		action_cancelled.emit(current_action)
	_start(action_id, blend_seconds)
	return OK

func pause() -> void:
	playing = false

func resume() -> void:
	if not current_action.is_empty() and time_seconds < duration_seconds() - EPSILON:
		playing = true
		active = true
	elif not current_action.is_empty() and _loops():
		playing = true
		active = true

func cancel() -> void:
	if active and not current_action.is_empty():
		action_cancelled.emit(current_action)
	playing = false
	active = false
	_clear_blend()
	_generation += 1

func clear() -> void:
	cancel()
	current_action = ""
	_clip = {}
	time_seconds = 0.0
	cycle = 0
	actions.clear()
	definition.clear()
	_human_names.clear()
	_item_names.clear()
	human_player = null
	item_player = null

func seek_seconds(seconds: float) -> void:
	# Scrubbing never emits gameplay events or completion/cancellation signals.
	if current_action.is_empty():
		return
	_clear_blend()
	time_seconds = clampf(seconds, 0.0, duration_seconds())
	_sample()

func seek_frame(frame: float) -> void:
	seek_seconds(frame / float(definition.get("fps", 60.0)))

func step_frames(amount: int) -> void:
	pause()
	seek_frame(roundf(current_frame()) + float(amount))

func duration_seconds() -> float:
	return float(_clip.get("frame_end", 0.0)) / float(definition.get("fps", 60.0))

func current_frame() -> float:
	return time_seconds * float(definition.get("fps", 60.0))

func is_transitioning() -> bool:
	return _blend_duration > EPSILON

func transition_progress() -> float:
	return _blend_elapsed / _blend_duration if is_transitioning() else 1.0

func _process(delta: float) -> void:
	if auto_process:
		advance(delta)

func advance(delta_seconds: float) -> void:
	if not playing or current_action.is_empty() or not is_finite(delta_seconds) or delta_seconds <= 0.0:
		return
	if not is_finite(speed) or speed <= 0.0:
		return
	var remaining := delta_seconds * speed
	while playing and remaining > EPSILON:
		if is_transitioning():
			var blend_generation := _generation
			var blend_step := minf(remaining, _blend_duration - _blend_elapsed)
			_blend_elapsed += blend_step
			remaining -= blend_step
			var weight := clampf(_blend_elapsed / _blend_duration, 0.0, 1.0)
			_apply_blend(weight * weight * (3.0 - 2.0 * weight))
			pose_sampled.emit(current_action, 0.0, 0.0)
			if blend_generation != _generation or not playing:
				return
			if _blend_elapsed >= _blend_duration - EPSILON:
				_clear_blend()
				_emit_between(-EPSILON * 2.0, 0.0)
				if blend_generation != _generation or not playing:
					return
			else:
				return
			if remaining <= EPSILON:
				return
		var duration := duration_seconds()
		var available := maxf(0.0, duration - time_seconds)
		var step := minf(available, remaining)
		var previous := time_seconds
		var generation := _generation
		time_seconds = minf(duration, time_seconds + step)
		remaining -= step
		_sample()
		if generation != _generation or not playing:
			return
		_emit_between(previous, time_seconds)
		# A host signal handler may cancel/switch items during an event.
		if generation != _generation or not playing:
			return
		if time_seconds < duration - EPSILON:
			break
		if _loops():
			cycle += 1
			time_seconds = 0.0
			_sample()
			if generation != _generation or not playing:
				return
			action_looped.emit(current_action, cycle)
			if generation != _generation or not playing:
				return
			_emit_between(-EPSILON * 2.0, 0.0)
			if generation != _generation or not playing:
				return
		else:
			playing = false
			active = false
			var finished_action := current_action
			var return_action := String(_clip.get("return_action", ""))
			action_finished.emit(finished_action)
			if generation != _generation:
				return
			if auto_return and not return_action.is_empty():
				_start(return_action)
			else:
				break

func _start(action_id: String, blend_seconds: float = 0.0) -> void:
	var starting_poses := _capture_pose_targets(action_id) if blend_seconds > EPSILON else []
	_clear_blend()
	_generation += 1
	current_action = action_id
	_clip = actions[action_id]
	time_seconds = 0.0
	cycle = 0
	playing = true
	active = true
	var generation := _generation
	human_player.play(StringName(_human_names[action_id]), 0.0)
	if item_player != null:
		if not String(_item_names[action_id]).is_empty():
			item_player.play(StringName(_item_names[action_id]), 0.0)
		else:
			item_player.pause()
	_evaluate_pair()
	if not starting_poses.is_empty():
		_blend_duration = blend_seconds
		_blend_poses = starting_poses
		for row: Dictionary in _blend_poses:
			var skeleton := (row["skeleton"] as WeakRef).get_ref() as Skeleton3D
			row["to"] = skeleton.get_bone_pose(int(row["bone"]))
		_apply_blend(0.0)
	pose_sampled.emit(current_action, 0.0, 0.0)
	if generation != _generation or not playing:
		return
	action_started.emit(action_id)
	if generation == _generation and playing and not is_transitioning():
		_emit_between(-EPSILON * 2.0, 0.0)

func _sample() -> void:
	_evaluate_pair()
	pose_sampled.emit(current_action, time_seconds, current_frame())

func _evaluate_pair() -> void:
	# update_only suppresses imported method/audio events. All gameplay events
	# come exclusively from the JSON frame table through event_reached.
	human_player.seek(time_seconds, true, true)
	if item_player != null and not String(_item_names.get(current_action, "")).is_empty():
		item_player.seek(time_seconds, true, true)

func _capture_pose_targets(action_id: String) -> Array:
	var poses: Array = []
	var seen := {}
	var pairs: Array = [[human_player, String(_human_names[action_id])]]
	if item_player != null and not String(_item_names[action_id]).is_empty():
		pairs.append([item_player, String(_item_names[action_id])])
	for pair in pairs:
		var player: AnimationPlayer = pair[0]
		var animation := player.get_animation(pair[1])
		var animation_root := player.get_node(player.root_node)
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			if path.get_subname_count() != 1:
				continue
			var skeleton := animation_root.get_node_or_null(NodePath(String(path).get_slice(":", 0))) as Skeleton3D
			if skeleton == null:
				continue
			var bone := skeleton.find_bone(path.get_subname(0))
			if bone < 0:
				continue
			var key := str(skeleton.get_instance_id()) + ":" + str(bone)
			if seen.has(key):
				continue
			seen[key] = true
			poses.append({"skeleton": weakref(skeleton), "bone": bone, "from": skeleton.get_bone_pose(bone)})
	return poses

func _apply_blend(weight: float) -> void:
	for row: Dictionary in _blend_poses:
		var skeleton := (row["skeleton"] as WeakRef).get_ref() as Skeleton3D
		if not is_instance_valid(skeleton):
			continue
		var source: Transform3D = row["from"]
		var target: Transform3D = row["to"]
		var pose := source.interpolate_with(target, weight)
		var bone := int(row["bone"])
		skeleton.set_bone_pose_position(bone, pose.origin)
		skeleton.set_bone_pose_rotation(bone, pose.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(bone, pose.basis.get_scale())

func _clear_blend() -> void:
	_blend_duration = 0.0
	_blend_elapsed = 0.0
	_blend_poses.clear()

func _loops() -> bool:
	if repeat_override != null:
		return bool(repeat_override)
	return bool(_clip.get("loop", false))

func _emit_between(start: float, end: float) -> void:
	var generation := _generation
	var fps := float(definition["fps"])
	for source_event: Dictionary in _clip.get("events", []):
		var event_time := float(source_event["frame"]) / fps
		if event_time > start + EPSILON and event_time <= end + EPSILON:
			var data: Dictionary = source_event.get("data", {}).duplicate(true)
			data["item_id"] = String(definition["id"])
			data["action_id"] = current_action
			data["frame"] = int(source_event["frame"])
			data["time_seconds"] = event_time
			data["cycle"] = cycle
			data["generation"] = generation
			event_reached.emit(String(source_event["event"]), data)
			if generation != _generation or not playing:
				return

static func find_animation(player: AnimationPlayer, requested: String) -> String:
	if player.has_animation(requested):
		return requested
	var matched_name := ""
	for value in player.get_animation_list():
		var name := String(value)
		if name.ends_with("/" + requested):
			if not matched_name.is_empty():
				return "" # Ambiguous libraries are an integration error.
			matched_name = name
	return matched_name
