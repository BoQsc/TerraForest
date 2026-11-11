extends SceneTree
## A hit must play the flesh impact, except firearms which already do.
## Drives the real WorldAudio adapter and the real apply_hit path.

const ZombieWorld = preload("res://addons/characters/runtime/zombie_world.gd")
const Adapter = preload("res://addons/audio_runtime/world_audio.gd")
const Catalog = preload("res://addons/audio_runtime/catalog.gd")

var failures := 0
func check(ok: bool, label: String) -> void:
	if ok: print("PASS ", label)
	else: failures += 1; print("FAIL ", label)

class Actor extends CharacterBody3D:
	## Mirrors zombie.gd's contract that apply_hit validates against.
	var PARTS := {"torso": {"health": 180.0}, "head": {"health": 90.0}}
	var missing := {"torso": false, "head": false}
	var alive := true
	func receive_hit(_part: String, _damage: float, _point := Vector3.ZERO, _direction := Vector3.ZERO, _sever := false, _impact := "melee", _reaction := true, _animation := true) -> void:
		pass

class Awareness extends RefCounted:
	func provoke(_id, _target) -> void:
		pass

class Terrain extends Node:
	signal density_ray_received
	var epoch := 0
	var native_revision := 0
	var world_ready := true
	func request_density_ray(_a: Vector3, _b: Vector3, _token: int, _layers: int, _p: bool) -> bool:
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
	## Minimal surface the audio adapter touches during initialize().
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

var adapter: Node3D
var world
var actor: Actor
var game: Game

func playing(id: String) -> int:
	var n := 0
	for voice in adapter.audio.voices:
		if voice.node.playing and str(voice.id) == id: n += 1
	return n

func hit(impact: String, part := "torso") -> bool:
	adapter.audio.stop_sound("zombie.hit.flesh")
	# Clear both guards: the trigger's own and the adapter's 90 ms per-event one.
	world._flesh_ms = -1000000
	adapter.last_event_ms.erase("zombie.hit.flesh")
	return world.apply_hit({"zombie": actor, "part": part, "position": actor.global_position + Vector3.UP}, 10.0, Vector3.FORWARD, impact)

func _init() -> void:
	run.call_deferred()

func run() -> void:
	# Real scene shape: WorldAudio and Zombies are siblings under the world root.
	game = Game.new()
	game.name = "World"
	root.add_child(game)
	world = ZombieWorld.new()
	world.name = "Zombies"
	game.add_child(world)
	world.enabled = true
	world.awareness = Awareness.new()
	actor = Actor.new()
	world.add_child(actor)
	world.residents.append(actor)
	world.target = actor
	# The player must be in the tree: reset_world reads its global position.
	game.add_child(game.player)
	game.add_child(game.camera)
	game.add_child(game.session_menu)

	adapter = Adapter.new()
	adapter.name = "WorldAudio"
	game.add_child(adapter)
	adapter.game = game
	adapter.initialize()
	check(adapter.audio != null, "adapter initializes its playback")

	# The flesh impact must be declared and playable.
	var catalog: RefCounted = adapter.audio.catalog
	check(catalog.sounds.has("zombie.hit.flesh"), "zombie.hit.flesh is declared")
	var row: Dictionary = catalog.sounds.get("zombie.hit.flesh", {})
	check(str(row.get("files", [""])[0]).contains("critical_hit_3_220ms"), "flesh impact uses the approved clip")
	check(row.get("bus", "") == "Effects", "flesh impact plays on Effects")
	var stream: AudioStream = catalog.streams.get(row.get("files", [""])[0])
	check(stream != null and stream.get_length() > 0.2 and stream.get_length() < 0.3, "clip is a short hit, %.2fs" % (stream.get_length() if stream else -1.0))

	check(hit("melee"), "melee hit is accepted")
	check(playing("zombie.hit.flesh") == 1, "melee hit plays the flesh impact")

	check(hit("cutting"), "cutting hit is accepted")
	check(playing("zombie.hit.flesh") == 1, "cutting hit plays the flesh impact")

	# Gunfire already has its own flesh impact; this must not double it.
	check(hit("firearm"), "firearm hit is accepted")
	check(playing("zombie.hit.flesh") == 0, "firearm hits do not double the flesh impact")

	# A rejected hit stays silent.
	adapter.audio.stop_sound("zombie.hit.flesh")
	world._flesh_ms = -1000000
	check(not world.apply_hit({"zombie": actor, "part": "tail", "position": Vector3.UP}, 10.0, Vector3.FORWARD, "melee"), "unknown part is rejected")
	check(playing("zombie.hit.flesh") == 0, "a rejected hit plays nothing")

	# The repeat guard stops a flurry from stacking.
	adapter.audio.stop_sound("zombie.hit.flesh")
	adapter.last_event_ms.erase("zombie.hit.flesh")
	world._flesh_ms = Time.get_ticks_msec()
	world.apply_hit({"zombie": actor, "part": "torso", "position": actor.global_position + Vector3.UP}, 10.0, Vector3.FORWARD, "melee")
	check(playing("zombie.hit.flesh") == 0, "a second hit within the guard is skipped")

	world.queue_free(); adapter.queue_free()
	print("ZOMBIE_FLESH_HIT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
