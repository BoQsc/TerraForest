# SPDX-License-Identifier: 0BSD
extends SceneTree
const Catalog = preload("res://addons/audio_runtime/catalog.gd")
const Runtime = preload("res://addons/audio_runtime/audio_runtime.gd")
const BUILTIN := "res://addons/audio_runtime/packs/nox/pack.audio.module.json"
var checks := 0
var failures := 0
var folder := "user://mods/audio_check_" + str(Time.get_ticks_usec())

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL ", message)
	else: print("PASS ", message)

func write_pack(value: Dictionary) -> String:
	var path := folder + "/pack.audio.module.json"
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(JSON.stringify(value)); file.close()
	return path

func _initialize() -> void: run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var sample := FileAccess.get_file_as_bytes("res://addons/audio_runtime/packs/nox/grass_walk_01.wav.bin")
	var file := FileAccess.open(folder + "/sample.wav", FileAccess.WRITE); file.store_buffer(sample); file.close()
	var catalog := Catalog.new()
	check(catalog.prepare(PackedStringArray([BUILTIN])), "bundled raw WAV/Ogg content loads without editor imports")
	check(catalog.sounds.size() == 23 and catalog.streams.size() == 82, "curated pack has all definitions and recordings")
	check(catalog.resident_bytes < 5 * 1024 * 1024, "curated content remains below five MiB")
	check(catalog.resolve("movement.footstep", {"surface": "grass", "gait": "walk"}).id == "nox.step.grass.walk", "specific surface and gait resolve")
	check(catalog.resolve("movement.footstep", {"surface": "unknown"}).id == "nox.step.fallback", "unknown surface resolves declared fallback")
	check(catalog.resolve("unknown.event").is_empty(), "missing event is silent")
	check(catalog.prepare(PackedStringArray([BUILTIN, "res://mods/example_audio/pack.audio.module.json"])), "data-only example replaces bundled sound")
	check(catalog.sounds["nox.step.grass.walk"].gain_db == -18, "replacement changes selected definition")
	var row := {"id": "test.step", "event": "test.step", "files": ["sample.wav"], "limit": 32}
	var pack := {"schema": 1, "id": "test.audio", "sounds": [row]}
	var path := write_pack(pack)
	check(catalog.prepare(PackedStringArray([path])), "loose user audio pack loads")
	var invalids: Array[Dictionary] = []
	var bad: Dictionary = pack.duplicate(true); bad.schema = 99; invalids.append(bad)
	bad = pack.duplicate(true); bad.sounds[0].files = ["../sample.wav"]; invalids.append(bad)
	bad = pack.duplicate(true); bad.sounds[0].files = ["script.tres"]; invalids.append(bad)
	bad = pack.duplicate(true); bad.sounds[0].files = ["missing.wav"]; invalids.append(bad)
	bad = pack.duplicate(true); bad.sounds[0].gain_db = 999; invalids.append(bad)
	bad = pack.duplicate(true); bad.sounds[0].loop = "yes"; invalids.append(bad)
	bad = pack.duplicate(true); bad.requires = ["missing.pack"]; invalids.append(bad)
	bad = pack.duplicate(true); bad.sounds.append(row.duplicate(true)); invalids.append(bad)
	bad = pack.duplicate(true); bad.sounds[0].replace = true; invalids.append(bad)
	bad = pack.duplicate(true); bad.sounds[0].script = "evil.gd"; invalids.append(bad)
	for i in invalids.size():
		write_pack(invalids[i])
		check(not catalog.prepare(PackedStringArray([BUILTIN, path])) and catalog.sounds.is_empty() and catalog.streams.is_empty(), "invalid pack %d rejects atomically" % i)
	check(not catalog.prepare(PackedStringArray(["user://mods/../elsewhere.json"])), "manifest traversal rejects")
	check(catalog.prepare(PackedStringArray()), "removing all audio content is valid")
	var runtime := Runtime.new(); root.add_child(runtime)
	check(runtime.prepare(PackedStringArray([BUILTIN])), "runtime prepares fixed pools")
	var bed := runtime.start_loop("ambience.forest", {}, true)
	check(bed > 0 and runtime.stop(bed), "background admission can be cancelled before playback starts")
	await process_frame; await process_frame
	check(runtime.statistics().active == 0, "cancelled deferred background cannot return as a ghost voice")
	bed = runtime.start_loop("ambience.forest", {}, true)
	await process_frame; await process_frame
	check(runtime.beds[0].node.playing and runtime.stop(bed), "background starts normally after deferred admission")
	var before := -1
	var varied := true
	for i in 20:
		var handle := runtime.emit_event("movement.footstep", {"surface": "grass", "gait": "walk"})
		var chosen: int = runtime.previous["nox.step.grass.walk"]
		varied = varied and handle > 0 and chosen != before; before = chosen; runtime.stop(handle)
	check(varied, "random variants avoid immediate repeats")
	check(runtime.emit_event("movement.footstep", {"position": Vector3(10000, 0, 0)}) == 0, "distant effects cull before playback")
	check(runtime.emit_event("movement.footstep", {"position": Vector3(INF, 0, 0)}) == 0, "nonfinite sound position rejects")
	var first := runtime.start_loop("fire.burn")
	check(first > 0 and runtime.update_loop(first, Vector3(1, 0, 0)), "loop handle starts and moves")
	check(not runtime.update_loop(first, Vector3(500, 0, 0)) and not runtime.stop(first), "out-of-range loop retires and invalidates handle")
	var next := runtime.start_loop("fire.burn")
	check(next > first and not runtime.stop(first), "retired handles never alias new playback")
	runtime.set_enabled(false)
	check(runtime.statistics().active == 0 and runtime.emit_event("movement.footstep") == 0, "disable clears every voice and blocks new sounds")
	runtime.set_enabled(true)
	pack.sounds = []
	for i in 40: pack.sounds.append({"id": "test.sound%d" % i, "event": "test.sound%d" % i, "files": ["sample.wav"], "priority": i})
	write_pack(pack)
	check(runtime.prepare(PackedStringArray([path])), "custom event pack installs without gameplay changes")
	for i in 40: runtime.emit_event("test.sound%d" % i)
	check(runtime.statistics().active == 32 and runtime.voices.size() == 32, "overflow steals only lower-priority one-shots within fixed pool")
	check(runtime.emit_event("test.sound0") == 0, "low-priority overflow drops")
	runtime.clear()
	check(runtime.statistics().active == 0, "world reset clears transients")
	for i in 39: pack.sounds[i].loop = true
	write_pack(pack); runtime.prepare(PackedStringArray([path]))
	var loops := 0
	for i in 39:
		if runtime.start_loop("test.sound%d" % i) > 0: loops += 1
	check(loops == 8, "spatial loops leave capacity for immediate feedback")
	var background := 0
	for i in range(8, 39):
		if runtime.start_loop("test.sound%d" % i, {}, true) > 0: background += 1
	check(background == 4, "background layer capacity remains fixed")
	check(runtime.emit_event("test.sound39") > 0, "one-shot feedback remains available with both loop pools full")
	runtime.set_enabled(false)
	check(runtime.statistics().active == 0, "muting clears positional loops and background beds together")
	check(runtime.prepare(PackedStringArray()) and runtime.emit_event("test.sound0") == 0, "pack removal preserves a functional silent runtime")
	runtime.queue_free(); await process_frame
	# Let the engine audio thread retire stopped background playbacks before exit.
	await create_timer(.15).timeout
	DirAccess.remove_absolute(path); DirAccess.remove_absolute(folder + "/sample.wav"); DirAccess.remove_absolute(folder)
	print("AUDIO_RUNTIME checks=%d failures=%d" % [checks, failures]); quit(1 if failures else 0)
