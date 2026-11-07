# SPDX-License-Identifier: 0BSD
extends SceneTree
## A gun impact leaves a bullet hole: placed on the surface, facing out, capped
## and expiring on its own.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	ProjectSettings.set_setting("terraforest/session_arguments", PackedStringArray([
		"--world-slot=Crystal_Creek", "--no-zombies", "--max-fps=60", "--temporary",
	]))
	var game = load("res://demo/world.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	run.call_deferred(game)

func run(game) -> void:
	var waited := 0.0
	while waited < 120.0 and game.get("startup_complete") != true:
		await create_timer(1.0).timeout
		waited += 1.0
	var combat = game.combat
	check(combat != null and combat.holes != null, "bullet hole pool is attached to combat")
	if combat == null or combat.holes == null:
		quit(1)
		return
	var point: Vector3 = game.player.global_position + Vector3(0, 1, -3)
	combat.impact({"position": point, "normal": Vector3.UP}, Vector3.DOWN, 10, 4)
	var hole = null
	for entry: Dictionary in combat.holes.holes:
		if entry.node.visible and entry.node.global_position.distance_to(point) < 0.05: hole = entry.node
	check(hole != null, "a gun impact leaves a bullet hole at the hit point")
	check(hole != null and hole.global_basis.z.dot(Vector3.UP) < -0.9, "the hole faces out along the surface normal")
	for i in 200:
		combat.holes.add(point, Vector3.UP)
	check(combat.holes.get_child_count() == 96, "bullet holes are capped at the pool size")
	combat.holes._process(60.0)
	var visible_holes := 0
	for entry: Dictionary in combat.holes.holes:
		if entry.node.visible: visible_holes += 1
	check(visible_holes == 0, "holes expire after their lifetime")
	print("BULLET_HOLES checks=", checks, " failures=", failures)
	game.shutdown_requested = true
	await game.terrain.shutdown_after_edits()
	game.free()
	quit(1 if failures > 0 else 0)
