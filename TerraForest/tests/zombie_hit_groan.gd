extends SceneTree
## A hit must cut the idle groan short and hold that zombie back afterwards.
## Exercises the real runtime and the real trigger, not a copy of the logic.

const ZombieWorld = preload("res://addons/characters/runtime/zombie_world.gd")
const Runtime = preload("res://addons/audio_runtime/audio_runtime.gd")
const Catalog = preload("res://addons/audio_runtime/catalog.gd")

var failures := 0
func check(ok: bool, label: String) -> void:
	if ok: print("PASS ", label)
	else: failures += 1; print("FAIL ", label)

func _init() -> void:
	run.call_deferred()

func run() -> void:
	# 1. The runtime can stop a named one-shot while it is playing.
	var runtime: Node3D = Runtime.new()
	root.add_child(runtime)
	check(runtime.prepare(Catalog.enabled_paths("user://missing_enabled.cfg")), "shipped packs prepare")
	runtime.listener = Vector3.ZERO
	check(runtime.emit_event("zombie.vocal.idle", {"position": Vector3(2, 0, 0)}) > 0, "groan starts")
	var playing := 0
	for voice in runtime.voices:
		if voice.node.playing: playing += 1
	check(playing == 1, "one groan is active")
	check(runtime.stop_sound("zombie.vocal.idle") == 1, "hit stops the playing groan")
	var still := 0
	for voice in runtime.voices:
		if voice.node.playing: still += 1
	check(still == 0, "no groan keeps playing after the hit")
	check(runtime.stop_sound("zombie.vocal.idle") == 0, "stopping again is harmless")

	# 2. A hit pushes that zombie's next groan well beyond the normal interval.
	var world = ZombieWorld.new()
	world.name = "Zombies"
	root.add_child(world)
	var id := 4242
	world._groan_clock[id] = 0.0
	world._hush_groan(id)
	check(absf(float(world._groan_clock[id]) - 14.0) < 0.01, "hit defers the next groan, got %.1f s" % world._groan_clock[id])
	# Countdown still works and is far longer than the normal 5-11 s interval.
	var t := 0.0
	while t < 12.0:
		world._groan_clock[id] = maxf(0.0, float(world._groan_clock[id]) - 1.0 / 60.0)
		t += 1.0 / 60.0
	check(float(world._groan_clock[id]) > 1.0, "still held 12 s after the hit, %.1f s left" % world._groan_clock[id])
	world.queue_free()
	runtime.queue_free()
	print("ZOMBIE_HIT_GROAN failures=%d" % failures)
	quit(1 if failures > 0 else 0)
