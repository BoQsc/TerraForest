# SPDX-License-Identifier: 0BSD
extends RefCounted
## Apply the developer's Kaino audition choices to an admitted audio catalog.

const Decoder := preload("res://addons/audio_runtime/wav_decoder.gd")
const DEFAULT_SELECTION := "res://addons/audio_runtime/kaino_audition_selection.json"

static func apply(catalog: RefCounted, selection_path: String = DEFAULT_SELECTION) -> int:
	var path := selection_path
	if not FileAccess.file_exists(path): return 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("selection", {}) is Dictionary: return 0
	var selection: Dictionary = parsed.selection
	var applied := 0
	for id: Variant in selection:
		var key := str(id)
		if not catalog.sounds.has(key): continue
		var stream := Decoder.decode(str(selection[id]))
		if stream == null: continue
		var row: Dictionary = catalog.sounds[key]
		if row.loop:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
		var stream_key := str(selection[id]) + (":loop" if row.loop else ":once")
		catalog.streams[stream_key] = stream
		row.files = [stream_key]
		catalog.sounds[key] = row
		applied += 1
	return applied
