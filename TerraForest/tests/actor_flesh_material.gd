extends SceneTree
## Flesh material must sound for living entities, not only zombies. A melee hit
## on a human actor previously fell through to world.break.block, which is a
## masonry sound. Drive the real break_event so the mapping is what ships.

const Attack = preload("res://addons/player_runtime/world_attack.gd")

var failures := 0
func check(ok: bool, label: String) -> void:
	if ok: print("PASS ", label)
	else: failures += 1; print("FAIL ", label)

func _init() -> void:
	var attack = Attack.new()
	check(attack.break_event({"kind": "actor", "material": "other"}) == "zombie.hit.flesh", "a struck actor plays the flesh impact")
	check(attack.break_event({"kind": "tree"}) == "world.break.wood", "trees still break as wood")
	check(attack.break_event({"kind": "cover", "material": "stone"}) == "world.break.stone", "stone cover still breaks as stone")
	check(attack.break_event({"kind": "block", "material": "wood"}) == "world.break.wood", "wood blocks still break as wood")
	print("ACTOR_FLESH_MATERIAL failures=%d" % failures)
	quit(1 if failures > 0 else 0)
