# SPDX-License-Identifier: 0BSD
# Run graphically at fullscreen 1920x1080: the real E handler requires captured
# mouse input, which the headless display backend does not provide.
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+30000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"gameplay world starts")
	if not game.loading_active:
		game.fly=true;game._clear_motion()
		game.ecosystem.set_process(false)
		game.player.position=Vector3(0,100,5)
		game.camera.global_position=Vector3(0,101,5)
		game.camera.look_at(Vector3(0,101,0))
		var poses: Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(0,100,0))]
		game.ecosystem._replace_samples(Vector2i.ZERO,PackedInt64Array([1]),poses)
		game.vegetation.trunk_collision.set_collision_focus(Vector3(0,100,0))
		for tick in range(8): await physics_frame
		check(not game._harvest_aimed_tree() and game.vegetation.renderer.roots.has(1),"aimed tree beyond 2.5 metres is untouched")
		game.camera.global_position=Vector3(0,101,2)
		var wall:=StaticBody3D.new();wall.collision_layer=1
		var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,2,.2);collider.shape=box
		wall.add_child(collider);game.add_child(wall);wall.global_position=Vector3(0,101,1)
		for tick in range(2): await physics_frame
		check(not game._harvest_aimed_tree() and game.vegetation.renderer.roots.has(1),"terrain-layer occluder prevents harvesting through a wall")
		wall.free()
		for tick in range(2): await physics_frame
		game.terrain.changed_since_save=false
		game.fly=false;game.app_focused=true
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		var interaction:=InputEventKey.new();interaction.physical_keycode=KEY_E;interaction.pressed=true
		game._unhandled_input(interaction)
		check(game.ecosystem.harvest_state.contains(1),"E interaction resolves aimed trunk to stable harvested identity")
		check(game.terrain.changed_since_save and game.player_hud.inventory.can_afford(PackedInt64Array([102,68]),game.player_hud.inventory.snapshot().revision).ok,"harvest grants four wood over starter supply and marks autosave")
		check(not game._harvest_aimed_tree(),"removed collider cannot be harvested again")
	game.shutdown_requested=true
	await game.terrain.shutdown_after_edits()
	game.free()
	for frame in range(2): await process_frame
	print("HARVESTING_SCENE ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
