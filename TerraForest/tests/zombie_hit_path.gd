extends SceneTree
## Prove the real hit path silences the groan: apply_hit must hand every valid
## hit to the trigger, and _hush_groan must stop playback and defer the next one.
## Uses a stand-in live actor so the anatomy physics is not required.

const ZombieWorld = preload("res://addons/characters/runtime/zombie_world.gd")
const Runtime = preload("res://addons/audio_runtime/audio_runtime.gd")
const Catalog = preload("res://addons/audio_runtime/catalog.gd")

var failures := 0
func check(ok: bool, label: String) -> void:
	if ok: print("PASS ", label)
	else: failures += 1; print("FAIL ", label)

class Actor extends CharacterBody3D:
	## Mirrors zombie.gd's contract that apply_hit validates against.
	var PARTS := {"torso": {"health": 180.0}, "head": {"health": 90.0}}
	# zombie.gd records intact parts as missing=false; an absent key means severed.
	var missing := {"torso": false, "head": false}
	var alive := true
	var received := 0
	func receive_hit(_part: String, _damage: float, _point := Vector3.ZERO, _direction := Vector3.ZERO, _sever := false, _impact := "melee", _reaction := true, _animation := true) -> void:
		received += 1

class Awareness extends RefCounted:
	var provoked := 0
	func provoke(_id, _target) -> void:
		provoked += 1

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var runtime: Node3D = Runtime.new()
	runtime.name = "WorldAudio"
	root.add_child(runtime)
	check(runtime.prepare(Catalog.enabled_paths("user://missing_enabled.cfg")), "shipped packs prepare")
	runtime.listener = Vector3.ZERO

	var world = ZombieWorld.new()
	world.name = "Zombies"
	root.add_child(world)
	world.enabled = true
	world.awareness = Awareness.new()
	var actor := Actor.new()
	world.add_child(actor)
	world.residents.append(actor)
	world.target = actor
	var id: int = actor.get_instance_id()

	# Start a real groan, then land a real hit on that same resident.
	check(runtime.emit_event("zombie.vocal.idle", {"position": Vector3(2, 0, 0)}) > 0, "groan is playing before the hit")
	var hit := {"zombie": actor, "part": "torso", "position": actor.global_position + Vector3.UP}
	# Report each guard so a rejected hit is diagnosable rather than opaque.
	print("DIAG impact_ok=", "melee" in ["unarmed","melee","cutting","heavy","firearm"],
		" part_has=", actor.PARTS.has("torso"), " missing_torso=", actor.missing.get("torso", true),
		" pos_finite=", hit.position.is_finite())
	check(world.apply_hit(hit, 10.0, Vector3.FORWARD, "melee"), "apply_hit accepts a valid hit")
	check(actor.received == 1, "the hit reached the actor")
	var playing := 0
	for voice in runtime.voices:
		if voice.node.playing: playing += 1
	check(playing == 0, "the groan stops when the zombie is hit")
	check(absf(float(world._groan_clock[id]) - 14.0) < 0.01, "that zombie is held back after the hit, got %.1f s" % world._groan_clock[id])

	# An invalid hit must not silence anything.
	runtime.emit_event("zombie.vocal.idle", {"position": Vector3(2, 0, 0)})
	world._groan_clock[id] = 0.0
	check(not world.apply_hit({"zombie": actor, "part": "tail", "position": Vector3.UP}, 10.0, Vector3.FORWARD, "melee"), "an unknown body part is rejected")
	var after := 0
	for voice in runtime.voices:
		if voice.node.playing: after += 1
	check(after == 1, "a rejected hit leaves the groan playing")
	world.queue_free(); runtime.queue_free()
	print("ZOMBIE_HIT_PATH failures=%d" % failures)
	quit(1 if failures > 0 else 0)
