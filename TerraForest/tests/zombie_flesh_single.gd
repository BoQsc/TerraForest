extends SceneTree
## Does ONE accepted hit start one flesh voice or two? Closes the doubled-log
## question from the real game log that the existing tests cannot see.

const ZombieWorld = preload("res://addons/characters/runtime/zombie_world.gd")
const Adapter = preload("res://addons/audio_runtime/world_audio.gd")

var failures := 0
func check(ok: bool, label: String) -> void:
	if ok: print("PASS ", label)
	else: failures += 1; print("FAIL ", label)

class Actor extends CharacterBody3D:
	var PARTS := {"torso": {"health": 180.0}}
	var missing := {"torso": false}
	var alive := true
	func receive_hit(_p: String, _d: float, _a := Vector3.ZERO, _b := Vector3.ZERO, _c := false, _e := "melee", _f := true, _g := true) -> void:
		pass

class Awareness extends RefCounted:
	func provoke(_i, _t) -> void:
		pass

class Terrain extends Node:
	signal density_ray_received
	var epoch := 0
	var native_revision := 0
	var world_ready := true
	func request_density_ray(_a: Vector3, _b: Vector3, _t: int, _l: int, _p: bool) -> bool:
		return false

class Structures extends Node:
	var _models := {}
	var object_definitions := {}
	var blocks: Node

class Menu extends CanvasLayer:
	var built := false

class Player extends Node3D:
	var velocity := Vector3.ZERO

class Game extends Node3D:
	var terrain := Terrain.new()
	var structures := Structures.new()
	var temporary_world := true
	var loading_active := false
	var shutdown_requested := false
	var app_focused := true
	var benchmark_enabled := false
	var player := Player.new()
	var camera := Camera3D.new()
	var vegetation: Node
	var session_menu := Menu.new()
	var player_view: Node
	var player_life: Node
	var world_vehicle: Node
	var fire_collections: Array = []

func _init() -> void:
	run.call_deferred()

func flesh_voices(adapter) -> int:
	var n := 0
	for voice in adapter.audio.voices:
		if voice.node.playing and str(voice.id) == "zombie.hit.flesh": n += 1
	return n

func run() -> void:
	var game := Game.new()
	game.name = "World"
	root.add_child(game)
	var world = ZombieWorld.new()
	world.name = "Zombies"
	game.add_child(world)
	world.enabled = true
	world.awareness = Awareness.new()
	var actor := Actor.new()
	world.add_child(actor)
	world.residents.append(actor)
	world.target = actor
	game.add_child(game.player)
	game.add_child(game.camera)
	game.add_child(game.session_menu)

	var adapter: Node3D = Adapter.new()
	adapter.name = "WorldAudio"
	game.add_child(adapter)
	adapter.game = game
	adapter.initialize()
	check(adapter.audio != null, "adapter initializes")

	# A single accepted swing, with both guards cleared beforehand.
	world._flesh_ms = -1000000
	adapter.last_event_ms.erase("zombie.hit.flesh")
	adapter.audio.stop_sound("zombie.hit.flesh")
	var ok: bool = world.apply_hit({"zombie": actor, "part": "torso", "position": actor.global_position + Vector3.UP}, 10.0, Vector3.FORWARD, "melee")
	check(ok, "one accepted melee hit")
	check(flesh_voices(adapter) == 1, "exactly one flesh voice for one swing, got %d" % flesh_voices(adapter))

	# Anything also routed through break_event must not add a second flesh play.
	check(adapter.audio.played <= 1, "the adapter played at most one sound, got %d" % adapter.audio.played)

	world.queue_free(); game.queue_free()
	print("ZOMBIE_FLESH_SINGLE failures=%d" % failures)
	quit(1 if failures > 0 else 0)
