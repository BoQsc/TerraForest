extends RefCounted

const API_VERSION := 1
const MAX_MODULES := 32
var modules: Dictionary = {}
var providers: Dictionary = {}
var diagnostics: Array[Dictionary] = []

func register_manifest(path: String, trusted: bool = false) -> Dictionary:
	if not trusted: return _failure(path, "Executable modules must be explicitly trusted")
	if modules.size() >= MAX_MODULES: return _failure(path, "Module limit reached")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 65536: return _failure(path, "Missing or oversized manifest")
	var value: Variant = JSON.parse_string(file.get_as_text())
	if not value is Dictionary: return _failure(path, "Manifest must be a JSON object")
	var manifest: Dictionary = value
	var version: Variant = manifest.get("api", null)
	if not manifest.get("id", null) is String or (not version is int and not version is float):
		return _failure(path, "Expected string module identity and numeric API version")
	var identity: String = manifest.id
	if not valid_id(identity) or modules.has(identity) or version != API_VERSION:
		return _failure(path, "Duplicate identity or unsupported module API")
	var definitions: Variant = manifest.get("providers", [])
	if not definitions is Array or definitions.is_empty() or definitions.size() > 32:
		return _failure(path, "Expected 1–32 provider definitions")
	var staged := {}
	for definition: Variant in definitions:
		if not definition is Dictionary: return _failure(path, "Provider must be an object")
		if not definition.get("capability", null) is String or not definition.get("id", null) is String:
			return _failure(path, "Expected string capability and provider identities")
		var capability: String = definition.capability
		var provider: String = definition.id
		var key := capability + ":" + provider
		if not valid_id(capability) or not valid_id(provider) or providers.has(key) or staged.has(key):
			return _failure(path, "Invalid or duplicate provider identity")
		var descriptor: Dictionary = definition.duplicate(true)
		descriptor["module"] = identity
		descriptor["manifest"] = path
		staged[key] = descriptor
	modules[identity] = manifest.duplicate(true)
	providers.merge(staged)
	return {"ok": true, "module": identity, "providers": staged.size()}

func load_enabled(path: String = "user://mods/enabled.cfg") -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	var archives: Variant = config.get_value("modules", "trusted_packs", PackedStringArray())
	if not archives is PackedStringArray or archives.size() > MAX_MODULES:
		_failure(path, "trusted_packs must be a bounded PackedStringArray"); return
	for archive: String in archives:
		if not archive.begins_with("user://mods/") or archive.contains("..") or archive.get_extension().to_lower() != "pck":
			_failure(archive, "Expected a trusted PCK inside user://mods"); continue
		if not ProjectSettings.load_resource_pack(archive, false): _failure(archive, "Resource pack could not be mounted")
	var manifests: Variant = config.get_value("modules", "trusted_manifests", PackedStringArray())
	if not manifests is PackedStringArray or manifests.size() > MAX_MODULES:
		_failure(path, "trusted_manifests must be a bounded PackedStringArray"); return
	for manifest: String in manifests:
		if manifest.contains("..") or (not manifest.begins_with("res://") and not manifest.begins_with("user://mods/")):
			_failure(manifest, "Module manifest must be bundled or inside user://mods"); continue
		register_manifest(manifest, true)

func entries(capability: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in providers:
		if key.begins_with(capability + ":"): result.append(providers[key].duplicate(true))
	result.sort_custom(func(first: Dictionary, second: Dictionary): return first.id < second.id)
	return result

static func valid_id(identity: String) -> bool:
	if identity.is_empty() or identity.length() > 96: return false
	for character: String in identity:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789._-": return false
	return true

func _failure(path: String, reason: String) -> Dictionary:
	var result := {"ok": false, "path": path, "reason": reason}
	diagnostics.append(result)
	return result
