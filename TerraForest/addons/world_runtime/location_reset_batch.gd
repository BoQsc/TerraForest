# SPDX-License-Identifier: 0BSD
extends RefCounted

const KINDS := ["field", "cube", "cell", "placement", "door", "damage", "container", "resident", "corpse", "harvest", "ground", "water"]
const MAX_OPERATIONS := 512
const MAX_BYTES := 64 * 1024 * 1024
const MAX_PATCH_BYTES := 16 * 1024 * 1024

var _operations: Array = []
var _owners: Dictionary = {}
var _phase := "idle"
var _reason := ""
var _cursor := 0
var _applied := 0
var _bytes := 0
var _elapsed_us := 0
var _maximum_step_us := 0

func status() -> Dictionary:
	return {"phase": _phase, "reason": _reason, "applied": _applied, "remaining": _operations.size() - _cursor if _phase == "applying" else _cursor if _phase == "rolling_back" else 0, "bytes": _bytes, "elapsed_us": _elapsed_us, "maximum_step_us": _maximum_step_us, "terminal": _phase in ["restored", "rolled_back", "rejected", "recovery_required"]}

func _reject(reason: String) -> Dictionary:
	_phase = "rejected"
	_reason = reason
	_operations.clear()
	_owners.clear()
	_bytes = 0
	return status()

func _state(owner: Object, kind: String) -> Dictionary:
	return owner.call(kind + "_patch_state") if is_instance_valid(owner) else {}

func _same_owners() -> bool:
	for row: Dictionary in _owners.values():
		if not is_instance_valid(row.target) or _state(row.target, row.kind) != row.token:
			return false
	return true

func _refresh(owner: Object) -> void:
	for row: Dictionary in _owners.values():
		if row.target == owner:
			row.token = _state(owner, row.kind)

func _valid_arguments(kind: String, arguments: Array) -> bool:
	if kind in ["field", "cube", "cell", "placement", "water"]:
		return arguments.size() == 2 and arguments[0] is Vector3i and arguments[1] is Vector3i
	if kind == "ground":
		return arguments.size() == 2 and arguments[0] is AABB and arguments[1] is PackedInt64Array
	if kind == "corpse":
		return arguments.size() == 2 and arguments[0] is PackedInt64Array and arguments[1] is PackedInt64Array
	return arguments.size() == 1 and (arguments[0] is PackedStringArray if kind == "damage" else arguments[0] is PackedInt64Array)

func prepare(entries: Array) -> Dictionary:
	if _phase != "idle":
		return status()
	if entries.is_empty() or entries.size() > MAX_OPERATIONS:
		return _reject("operation_limit")
	for value: Variant in entries:
		if not value is Dictionary or not value.get("target") is Object or not value.get("kind") is String or not value.get("arguments") is Array or not value.get("original") is PackedByteArray:
			return _reject("invalid_operation")
		var owner: Object = value.target
		var kind: String = value.kind
		if not is_instance_valid(owner) or not kind in KINDS:
			return _reject("invalid_owner")
		if not _valid_arguments(kind, value.arguments):
			return _reject("invalid_arguments:" + kind)
		for method: String in [kind + "_patch_state", "capture_" + kind + "_patch", "validate_" + kind + "_patch", "restore_" + kind + "_patch"]:
			if not owner.has_method(method):
				return _reject("missing_owner_method")
		var original: PackedByteArray = value.original.duplicate()
		if original.is_empty() or original.size() > MAX_PATCH_BYTES or not owner.call("validate_" + kind + "_patch", original):
			return _reject("invalid_original:" + kind)
		var token := _state(owner, kind)
		if not token.get("revision") is int or not token.get("owner", token.get("epoch")) is int:
			return _reject("invalid_owner_token")
		var identity := str(owner.get_instance_id()) + ":" + kind
		if _owners.has(identity) and _owners[identity].token != token:
			return _reject("owner_changed_during_capture")
		_owners[identity] = {"target": owner, "kind": kind, "token": token}
		var arguments: Array = value.arguments.duplicate(true)
		arguments.append(token.revision)
		arguments.append(token.get("owner", token.get("epoch", -1)))
		var undo: PackedByteArray = owner.callv("capture_" + kind + "_patch", arguments)
		if undo.is_empty() or undo.size() > MAX_PATCH_BYTES or not owner.call("validate_" + kind + "_patch", undo):
			return _reject("undo_unavailable:" + kind)
		_bytes += original.size() + undo.size()
		if _bytes > MAX_BYTES:
			return _reject("byte_limit")
		_operations.append({"target": owner, "kind": kind, "original": original, "undo": undo, "identity": identity})
	if not _same_owners():
		return _reject("owner_changed_during_capture")
	_phase = "prepared"
	return status()

func cancel() -> Dictionary:
	if _phase in ["prepared", "applying", "restored"]:
		_phase = "rolling_back"
		_reason = "cancelled"
	return status()

func advance() -> Dictionary:
	var started := Time.get_ticks_usec()
	_advance_one()
	var elapsed := Time.get_ticks_usec() - started
	_elapsed_us += elapsed
	_maximum_step_us = maxi(_maximum_step_us, elapsed)
	return status()

func _advance_one() -> void:
	if not _phase in ["prepared", "applying", "rolling_back"]:
		return
	if not _same_owners():
		_phase = "rejected" if _cursor == 0 else "recovery_required"
		_reason = "owner_changed"
		return
	if _phase == "prepared":
		_phase = "applying"
	if _phase == "rolling_back" and _cursor == 0:
		_phase = "rolled_back"
		return
	var rollback := _phase == "rolling_back"
	var operation: Dictionary = _operations[_cursor - 1 if rollback else _cursor]
	var token: Dictionary = _owners[operation.identity].token
	var result: Dictionary = operation.target.call("restore_" + operation.kind + "_patch", operation.undo if rollback else operation.original, token.revision, token.get("owner", token.get("epoch", -1)))
	if not result.get("ok", false):
		_reason = ("rollback_failed:" if rollback else "restore_failed:") + operation.kind + ":" + str(result.get("reason", "unknown"))
		_phase = "recovery_required" if rollback or not _same_owners() else "rolling_back"
		return
	_refresh(operation.target)
	if not _same_owners():
		_phase = "recovery_required"
		_reason = "owner_changed_during_restore"
		return
	if rollback:
		_cursor -= 1
		if _cursor == 0:
			_phase = "rolled_back"
	else:
		_cursor += 1
		_applied += 1
		if _cursor == _operations.size():
			_phase = "restored"
