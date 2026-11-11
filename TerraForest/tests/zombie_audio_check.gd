extends SceneTree
## Verify the approved zombie groan is admitted, resolves to the approved file,
## stays quiet, and that the curated NOX pack is unchanged.

const Catalog = preload("res://addons/audio_runtime/catalog.gd")
const KainoMap = preload("res://addons/audio_runtime/kaino_audition_map.gd")
const NOX := "res://addons/audio_runtime/packs/nox/pack.audio.module.json"
const ZOMBIE := "res://addons/audio_runtime/packs/Kaino/zombie.pack.audio.module.json"
const GROAN := "res://addons/audio_runtime/packs/Kaino/1/Zombie Groan 1 - Kaino.wav"

var failures := 0
func check(ok: bool, label: String) -> void:
	if ok: print("PASS ", label)
	else: failures += 1; print("FAIL ", label)

func _init() -> void:
	var nox := Catalog.new()
	check(nox.prepare(PackedStringArray([NOX])), "curated NOX pack still loads")
	check(nox.streams.size() == 82, "curated NOX recording count unchanged (82), got %d" % nox.streams.size())
	check(not nox.sounds.has("zombie.vocal.idle"), "zombie sound is not in the curated pack")

	# The pack references a 16-bit PCM conversion of the approved recording.
	var both := Catalog.new()
	var paths := Catalog.enabled_paths("user://missing_enabled.cfg")
	check(both.prepare(paths), "enabled_paths admits the zombie pack")
	check(both.sounds.has("zombie.vocal.idle"), "zombie.vocal.idle is admitted")
	var row: Dictionary = both.sounds["zombie.vocal.idle"]
	check(str(row.files[0]).contains("zombie_groan_1.wav"), "resolves to the approved groan, got %s" % str(row.files[0]))
	check(both.streams.has(row.files[0]) and both.streams[row.files[0]] != null, "approved groan is decoded and playable")
	var stream: AudioStream = both.streams[row.files[0]]
	check(stream.get_length() > 3.0 and stream.get_length() < 4.5, "groan length is ~3.7s, got %.2fs" % stream.get_length())
	check(row.bus == "Voices", "plays on the Voices bus")
	check(float(row.gain_db) == -10.0, "gain is -10 dB, got %s" % str(row.gain_db))
	check(int(row.limit) == 2, "at most two groans overlap, got %s" % str(row.limit))
	check(float(row.range) == 26.0, "range is 26 m, got %s" % str(row.range))
	check(not row.loop, "does not loop")

	# The converted file must match the approved source sample-for-sample.
	var source: AudioStreamWAV = KainoMap.Decoder.decode(GROAN)
	var converted: AudioStreamWAV = AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes("res://addons/audio_runtime/packs/Kaino/zombie_groan_1.wav"))
	check(source != null and converted != null and source.data == converted.data, "converted audio preserves the approved samples")

	print("ZOMBIE_AUDIO failures=%d" % failures)
	quit(1 if failures > 0 else 0)
