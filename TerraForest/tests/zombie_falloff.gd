extends SceneTree
## Spatial falloff guard. A zombie attacking stands about 1 m away; with a tiny
## unit_size every sound near the listener played at its full gain, so a groan
## sitting behind footsteps became the loudest thing in the mix.

const Runtime = preload("res://addons/audio_runtime/audio_runtime.gd")
const Catalog = preload("res://addons/audio_runtime/catalog.gd")

var failures := 0
func check(ok: bool, label: String) -> void:
	if ok: print("PASS ", label)
	else: failures += 1; print("FAIL ", label)

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var folder := "user://mods/zombie_falloff_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var sample := FileAccess.get_file_as_bytes("res://addons/audio_runtime/packs/Kaino/zombie_groan_1.wav")
	var file := FileAccess.open(folder + "/groan.wav", FileAccess.WRITE); file.store_buffer(sample); file.close()
	var pack := {"schema": 1, "id": "test.falloff", "sounds": [
		{"id": "zombie.vocal.idle", "event": "zombie.vocal.idle", "files": ["groan.wav"],
		 "gain_db": -10, "range": 26, "limit": 2, "priority": 25}]}
	var manifest := folder + "/pack.audio.module.json"
	var out := FileAccess.open(manifest, FileAccess.WRITE)
	out.store_string(JSON.stringify(pack)); out.close()

	var runtime: Node3D = Runtime.new()
	root.add_child(runtime)
	check(runtime.prepare(Catalog.enabled_paths("user://missing_enabled.cfg")), "shipped packs prepare")
	runtime.listener = Vector3.ZERO
	check(runtime.emit_event("zombie.vocal.idle", {"position": Vector3(1, 0, 0)}) > 0, "groan at 1 m plays")
	var node: AudioStreamPlayer3D
	for voice in runtime.voices:
		if voice.node.playing: node = voice.node
	check(node != null, "voice is a 3D player")
	# Close-in level is what the player complains about, so assert it directly:
	# at an attacker's reach the player must be well below the sound's own gain.
	check(node.volume_db <= -20.0, "close groan is quiet, gain %.1f dB" % node.volume_db)
	check(node.volume_db < -8.0, "close groan sits below a footstep, gain %.1f dB" % node.volume_db)
	# unit_size is the radius still played at full gain; keeping it small is what
	# makes the sound fall away as you close the distance.
	check(node.unit_size <= 3.0, "near-field stays short so close sounds fall off, got %.2f m" % node.unit_size)
	check(node.unit_size < float(node.max_distance), "attenuation starts before the cull range")
	check(node.max_distance == 26.0, "cull range still 26 m, got %.1f" % node.max_distance)
	runtime.queue_free()
	print("ZOMBIE_FALLOFF failures=%d" % failures)
	quit(1 if failures > 0 else 0)
