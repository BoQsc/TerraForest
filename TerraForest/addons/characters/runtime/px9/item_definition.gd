# SPDX-License-Identifier: CC0-1.0
# Engine-independent JSON contract shared by the importer, preview and runtime.
extends RefCounted

const SCHEMA := "bg5.first_person_item.v1"

static func load_definition(path: String) -> Dictionary:
	var parser := JSON.new()
	var error := parser.parse(FileAccess.get_file_as_string(path))
	if error != OK or not parser.data is Dictionary:
		push_error("Item definition is not valid JSON: " + path)
		return {}
	var definition: Dictionary = parser.data
	var problems := validate(definition)
	if not problems.is_empty():
		push_error("Item definition: " + "; ".join(problems))
		return {}
	return definition

static func validate(definition: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	if String(definition.get("schema", "")) != SCHEMA:
		problems.append("unsupported schema")
	if String(definition.get("id", "")).is_empty():
		problems.append("id is required")
	var fps := float(definition.get("fps", 0.0))
	if not is_finite(fps) or fps <= 0.0:
		problems.append("fps must be positive")
	var files: Dictionary = definition.get("files", {})
	for key in ["human_reference", "human_animation_source", "human_library", "item_scene"]:
		if String(files.get(key, "")).is_empty():
			problems.append("files." + key + " is required")
	var mount: Dictionary = definition.get("mount", {})
	if String(mount.get("bone", "")).is_empty():
		problems.append("mount.bone is required")
	if String(mount.get("space", "")) not in ["hand_local", "human_rest"]:
		problems.append("mount.space must be hand_local or human_rest")
	var transform: Dictionary = mount.get("transform", {})
	var columns: Array = transform.get("basis_columns", [])
	if columns.size() != 3:
		problems.append("mount.transform requires three basis columns")
	else:
		for column in columns:
			if not _is_vector(column):
				problems.append("mount basis column must contain three finite numbers")
	if not _is_vector(transform.get("origin", [])):
		problems.append("mount origin must contain three finite numbers")
	if columns.size() == 3 and _is_vector(columns[0]) and _is_vector(columns[1]) and _is_vector(columns[2]):
		var basis := Basis(vector(columns[0]), vector(columns[1]), vector(columns[2]))
		if not is_finite(basis.determinant()) or absf(basis.determinant()) < 0.000001:
			problems.append("mount transform must be invertible")
	var actions: Array = definition.get("actions", [])
	if actions.is_empty():
		problems.append("at least one action is required")
	var ids := {}
	for action_value in actions:
		if not action_value is Dictionary:
			problems.append("each action must be an object")
			continue
		var action: Dictionary = action_value
		var id := String(action.get("id", ""))
		if id.is_empty() or ids.has(id):
			problems.append("action ids must be nonempty and unique: " + id)
		ids[id] = true
		if String(action.get("human_clip", "")).is_empty():
			problems.append(id + ": human_clip is required")
		# An ordinary rigid tool can omit item_clip and its AnimationPlayer.
		var frame_end := float(action.get("frame_end", -1.0))
		if frame_end < 1.0 or frame_end != floorf(frame_end):
			problems.append(id + ": frame_end must be a positive integer")
		var previous := -1
		for event_value in action.get("events", []):
			if not event_value is Dictionary:
				problems.append(id + ": event must be an object")
				continue
			var event: Dictionary = event_value
			var frame := float(event.get("frame", -1.0))
			if frame < 0.0 or frame > frame_end or frame != floorf(frame):
				problems.append(id + ": event frame outside clip or not an integer")
			if int(frame) < previous:
				problems.append(id + ": events must be sorted by frame")
			previous = int(frame)
			if String(event.get("event", "")).is_empty():
				problems.append(id + ": event name is required")
	for action_value in actions:
		if action_value is Dictionary:
			var return_action := String(action_value.get("return_action", ""))
			if not return_action.is_empty() and not ids.has(return_action):
				problems.append("unknown return_action: " + return_action)
	if not ids.has(String(definition.get("default_action", ""))):
		problems.append("default_action must name a declared action")
	return problems

static func vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func transform(value: Dictionary) -> Transform3D:
	var columns: Array = value["basis_columns"]
	return Transform3D(Basis(vector(columns[0]), vector(columns[1]), vector(columns[2])), vector(value["origin"]))

static func action_map(definition: Dictionary) -> Dictionary:
	var result := {}
	for action: Dictionary in definition["actions"]:
		result[String(action["id"])] = action
	return result

static func resolve_file(definition_path: String, value: String) -> String:
	if value.begins_with("res://") or value.begins_with("user://") or value.is_absolute_path():
		return value
	return definition_path.get_base_dir().path_join(value).simplify_path()

static func _is_vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component in value:
		if not (component is float or component is int) or not is_finite(float(component)):
			return false
	return true
