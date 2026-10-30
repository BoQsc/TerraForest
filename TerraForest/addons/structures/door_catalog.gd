# SPDX-License-Identifier: 0BSD
extends RefCounted
const KEY := "architecture/wooden_door/v1"
const Catalog = preload("res://addons/structures/object_catalog.gd")
static var _builtin_definition: Dictionary = {}

static func builtin_definition() -> Dictionary:
	if _builtin_definition.is_empty():
		var catalog := Catalog.new()
		if catalog.prepare(): _builtin_definition = catalog.definitions[KEY]
	return _builtin_definition.duplicate(true)

# Compatibility entry points for standalone addon clients and older fixtures.
static func recipe() -> PackedInt64Array:
	return Catalog.recipe(builtin_definition().get("recipe", {}))

static func salvage() -> PackedInt64Array:
	return Catalog.recipe(builtin_definition().get("salvage", {}))

static func register(world: Node3D) -> Dictionary:
	var entries := register_all(world)
	return entries[0] if not entries.is_empty() else {}

static func register_all(world: Node3D, config_path: String = "") -> Array[Dictionary]:
	var catalog := Catalog.new()
	var entries: Array[Dictionary] = []
	if catalog.prepare(config_path): entries = catalog.register_all(world)
	if entries.is_empty(): push_error("Door content: " + "; ".join(catalog.diagnostics))
	return entries
