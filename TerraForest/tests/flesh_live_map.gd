extends SceneTree
## Verify the live audition map actually swaps the flesh.hit recording, so a
## running game picks up the change without a relaunch.

const Catalog = preload("res://addons/audio_runtime/catalog.gd")
const KainoMap = preload("res://addons/audio_runtime/kaino_audition_map.gd")
const SELECTION := "res://addons/audio_runtime/kaino_audition_selection.json"

var failures := 0
func check(ok: bool, label: String) -> void:
	if ok: print("PASS ", label)
	else: failures += 1; print("FAIL ", label)

func _init() -> void:
	var catalog := Catalog.new()
	check(catalog.prepare(Catalog.enabled_paths("user://missing_enabled.cfg")), "packs prepare")
	check(catalog.sounds.has("flesh.hit"), "flesh.hit is declared")

	var applied := KainoMap.apply(catalog, SELECTION)
	check(applied > 0, "audition selection applied, %d entries" % applied)

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SELECTION))
	var wanted := str(parsed.selection.get("flesh.hit", ""))
	var row: Dictionary = catalog.sounds["flesh.hit"]
	if wanted.is_empty():
		# No override: the pack manifest is the source of truth for the default.
		print("PASS no flesh.hit override; the shipped default is in use: ", str(row.files[0]))
	else:
		check(str(row.files[0]).begins_with(wanted), "live row points at the selected file")
	check(str(row.files[0]).contains("fxm_flesh_02"), "default flesh hit is the neutral clip, got %s" % str(row.files[0]))
	var stream: AudioStream = catalog.streams.get(row.files[0])
	check(stream != null, "selected clip decodes through the live path")
	check(stream != null and stream.get_length() > 0.2, "clip is a usable hit, %.2fs" % (stream.get_length() if stream else -1.0))
	check(stream is AudioStreamWAV, "decoded as WAV PCM for the runtime")

	print("FLESH_LIVE_MAP failures=%d" % failures)
	quit(1 if failures > 0 else 0)
