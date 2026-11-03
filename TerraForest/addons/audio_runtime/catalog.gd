# SPDX-License-Identifier: 0BSD
extends RefCounted
## Startup-only, data-only content admission. No scripts/scenes/PCKs are loaded.
const MAX_PACKS := 16
const MAX_SOUNDS := 256
const MAX_VARIANTS := 16
const MAX_BYTES := 48 * 1024 * 1024
var sounds: Dictionary = {}
var streams: Dictionary = {}
var packs: Array[String] = []
var diagnostics: Array[String] = []
var resident_bytes := 0

func prepare(paths: PackedStringArray) -> bool:
	sounds.clear(); streams.clear(); packs.clear(); diagnostics.clear(); resident_bytes = 0
	if paths.size() > MAX_PACKS: return _fail("Too many audio packs")
	for path in paths:
		if not _admit(path):
			sounds.clear(); streams.clear(); packs.clear(); resident_bytes = 0
			return false
	return true

func _admit(path: String) -> bool:
	if not _manifest_path(path): return _fail("Audio manifest must be bundled or beneath user://mods: " + path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1024 * 1024: return _fail("Missing or oversized audio manifest: " + path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: return _fail("Audio manifest must be an object")
	var pack: Dictionary = parsed
	if not _fields(pack, ["schema", "id", "requires", "sounds"]) or pack.get("schema") != 1 or not valid_id(pack.get("id")) or pack.id in packs:
		return _fail("Unsupported schema or duplicate/invalid audio pack")
	var requirements: Variant = pack.get("requires", [])
	if not requirements is Array or requirements.size() > MAX_PACKS: return _fail("Invalid audio dependencies")
	for dependency: Variant in requirements:
		if not dependency is String or dependency not in packs: return _fail("Audio dependency must be enabled earlier")
	if not pack.get("sounds") is Array or pack.sounds.size() > MAX_SOUNDS: return _fail("Invalid audio sound list")
	var replaced := {}
	for value: Variant in pack.sounds:
		if not value is Dictionary: return _fail("Audio sound must be an object")
		var row: Dictionary = value.duplicate(true)
		if not _fields(row, ["id", "event", "match", "files", "bus", "gain_db", "pitch", "range", "priority", "limit", "loop", "replace"]): return _fail("Unknown sound field")
		if not valid_id(row.get("id")) or not valid_id(row.get("event")): return _fail("Invalid sound/event ID")
		var replacement: Variant = row.get("replace", false)
		if not replacement is bool or replacement != sounds.has(row.id) or replaced.has(row.id): return _fail("Duplicate sounds require one explicit replacement: " + row.id)
		if not replacement and sounds.size() >= MAX_SOUNDS: return _fail("Sound definition budget exceeded")
		var selectors: Variant = row.get("match", {})
		if not selectors is Dictionary or selectors.size() > 8: return _fail("Invalid sound selectors")
		for key: Variant in selectors:
			if not valid_id(key) or not valid_id(selectors[key]): return _fail("Selectors must be bounded identifiers")
		row["match"] = selectors
		row["bus"] = row.get("bus", "Effects")
		row["gain_db"] = row.get("gain_db", -6.0)
		row["pitch"] = row.get("pitch", 1.03)
		row["range"] = row.get("range", 24.0)
		row["priority"] = row.get("priority", 50)
		row["limit"] = row.get("limit", 4)
		row["loop"] = row.get("loop", false)
		if row.bus not in ["Effects", "Ambience", "Voices", "UI"] or not number(row.gain_db, -60, 0) or not number(row.pitch, 1, 1.15) or not number(row.range, 1, 512) or not number(row.priority, 0, 100) or not number(row.limit, 1, 32) or row.limit != int(row.limit) or not row.loop is bool:
			return _fail("Invalid sound playback settings")
		if not row.get("files") is Array or row.files.is_empty() or row.files.size() > MAX_VARIANTS: return _fail("Expected 1–16 audio files")
		var filenames: Array[String] = []
		for name: Variant in row.files:
			if not name is String or name.is_empty() or name.length() > 200 or name.is_absolute_path() or name.contains(":") or name.contains("..") or name.contains("\\") or name.trim_suffix(".bin").get_extension().to_lower() not in ["wav", "ogg"]:
				return _fail("Audio file must be a relative WAV or Ogg path")
			var full := path.get_base_dir().path_join(name)
			var key := full + (":loop" if row.loop else ":once")
			if not streams.has(key):
				if not FileAccess.file_exists(full): return _fail("Missing audio file: " + full)
				var audio_file := FileAccess.open(full, FileAccess.READ)
				if audio_file == null or audio_file.get_length() == 0 or audio_file.get_length() > 16 * 1024 * 1024 or resident_bytes + audio_file.get_length() > MAX_BYTES: return _fail("Missing audio file or resident byte budget exceeded: " + full)
				var data := audio_file.get_buffer(audio_file.get_length())
				var stream: AudioStream
				if full.trim_suffix(".bin").get_extension().to_lower() == "wav":
					var wav := AudioStreamWAV.load_from_buffer(data)
					if wav != null:
						wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if row.loop else AudioStreamWAV.LOOP_DISABLED
						if row.loop: wav.loop_begin = 0; wav.loop_end = roundi(wav.get_length() * wav.mix_rate)
					stream = wav
				else:
					var ogg := AudioStreamOggVorbis.load_from_buffer(data)
					if ogg != null: ogg.loop = row.loop
					stream = ogg
				if stream == null or not number(stream.get_length(), .005, 120): return _fail("Unsupported or overlong audio: " + full)
				streams[key] = stream; resident_bytes += data.size()
			filenames.append(key)
		row["files"] = filenames; row["pack"] = pack.id
		sounds[row.id] = row; replaced[row.id] = true
	packs.append(pack.id)
	return true

func resolve(event: String, context: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	for id: String in sounds:
		var row: Dictionary = sounds[id]
		if row.event != event: continue
		var matches := true
		for key: String in row.match:
			if str(context.get(key, "")) != row.match[key]: matches = false; break
		if matches and (best.is_empty() or row.match.size() > best.match.size() or (row.match.size() == best.match.size() and row.id < best.id)): best = row
	return best.duplicate(true)

static func enabled_paths(config_path: String = "user://mods/enabled.cfg") -> PackedStringArray:
	var paths := PackedStringArray()
	var builtin := "res://addons/audio_runtime/packs/nox/pack.audio.module.json"
	if FileAccess.file_exists(builtin): paths.append(builtin)
	var config := ConfigFile.new()
	if config.load(config_path) == OK:
		var external: Variant = config.get_value("audio", "manifests", PackedStringArray())
		if external is PackedStringArray:
			for path: String in external: paths.append(path)
		else: paths.append("invalid:audio-manifests")
	return paths

static func valid_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 96: return false
	for character: String in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789._-": return false
	return true

static func number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(value) and value >= low and value <= high

static func _manifest_path(path: String) -> bool:
	return path.length() <= 240 and not path.contains("..") and not path.contains("\\") and path.ends_with(".json") and (path.begins_with("res://addons/audio_runtime/packs/") or path.begins_with("res://mods/") or path.begins_with("user://mods/"))

static func _fields(value: Dictionary, allowed: Array) -> bool:
	for key: Variant in value:
		if key not in allowed: return false
	return true

func _fail(reason: String) -> bool:
	if diagnostics.size() < 32: diagnostics.append(reason)
	return false
