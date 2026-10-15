# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
class Menu extends RefCounted:
	var opened:=false
	func visible_ui() -> bool:return opened
class Game extends Node3D:
	var structures: Node3D
	var camera:=Camera3D.new()
	var player:=CharacterBody3D.new()
	var player_hud=preload("res://addons/player_runtime/player_hud.gd").new()
	var storage=preload("res://addons/player_runtime/storage.gd").new()
	var doors=preload("res://addons/structures/door_interaction.gd").new()
	var session_menu:=Menu.new()
	var terrain: Dictionary={"world_ready":true,"pending_edit":false,"changed_since_save":false}
	var world_vehicle: Dictionary={"driving":false}
	var fly:=false
	var app_focused:=true
	var loading_active:=false
	var shutdown_requested:=false
	func _model_edit_available() -> bool:return app_focused and not loading_active and not shutdown_requested and not player_hud.inventory_open and not world_vehicle.driving and terrain.world_ready and not terrain.pending_edit
	func _show_lake_notice(_text: String) -> void:pass
	func _clear_motion() -> void:pass
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func settle() -> void:
	for i in 12:await physics_frame;await process_frame
func run() -> void:
	check(load("res://demo/world.tscn")!=null,"main world parses with shared building interaction")
	var game:=Game.new();root.add_child(game)
	game.structures=preload("res://addons/structures/structures_world.gd").new();game.add_child(game.structures)
	check(game.structures.prepare(),"native structures prepare")
	game.add_child(game.camera);game.add_child(game.player);game.add_child(game.player_hud);game.add_child(game.storage)
	game.player.position=Vector3(5,0,0);game.camera.position=Vector3(0.5,1,2)
	game.doors.game=game;game.doors.collection=preload("res://addons/structures/door_catalog.gd").register(game.structures).collection
	game.doors.state=ClassDB.instantiate("NativeHingedDoors")
	game.storage.game=game;game.storage.collection=preload("res://addons/structures/storage_catalog.gd").register(game.structures).collection
	game.storage.store=ClassDB.instantiate("NativeContainerStore");check(game.storage.store.configure(game.player_hud.inventory,16),"native container configured")
	var pose:=PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0])
	check(game.doors.collection.upsert_instances(PackedInt64Array([1]),pose),"door placed")
	game.doors.collection.set_collision_focus(Vector3.ZERO);await settle()
	var adapter=preload("res://demo/building_interaction.gd").new()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	adapter.update(game,0.1)
	check(game.player_hud.interaction_hint.text=="E · Open wooden door" and game.player_hud.interaction_hint.visible,"aimed closed door has visible open prompt")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://reports/building_interaction_hint")
		root.get_texture().get_image().save_png("res://reports/building_interaction_hint/door.png")
	check(adapter.interact(game) and game.doors.state.is_open(1),"same ray executes shown open action")
	await settle()
	game.camera.position=Vector3(2,1,-0.5);game.camera.look_at(Vector3(0,1,-0.5));adapter.update(game,0.1)
	check(game.player_hud.interaction_hint.text=="E · Close wooden door","open leaf has close prompt")
	game.session_menu.opened=true;adapter.update(game,0.001)
	check(not game.player_hud.interaction_hint.visible and not adapter.interact(game),"menu immediately hides and disables interaction")
	game.session_menu.opened=false;game.loading_active=true;adapter.update(game,0.001)
	check(not game.player_hud.interaction_hint.visible and not adapter.interact(game),"loading disables hint and action")
	game.loading_active=false
	# Camera changes between hint refresh and E must never toggle the old target.
	game.camera.look_at(Vector3(5,1,-0.5))
	check(not adapter.interact(game) and game.doors.state.is_open(1),"input repicks rather than using cached door")
	game.doors.collection.remove_instances(PackedInt64Array([1]))
	check(game.storage.collection.upsert_instances(PackedInt64Array([2]),pose),"chest placed")
	game.storage.collection.set_collision_focus(Vector3.ZERO)
	game.camera.position=Vector3(0,0.5,2);game.camera.rotation=Vector3.ZERO;await settle();adapter.update(game,0.1)
	check(game.player_hud.interaction_hint.text=="E · Open wooden chest","chest prompt resolves native identity")
	var wall:=StaticBody3D.new();wall.collision_layer=1
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,2,0.2);shape.shape=box;wall.add_child(shape);game.add_child(wall);wall.position=Vector3(0,0.5,1)
	await settle();adapter.update(game,0.1)
	check(not game.player_hud.interaction_hint.visible and not adapter.interact(game),"wall occludes prompt and chest action")
	wall.free();await settle()
	check(adapter.interact(game) and game.storage.opened and game.storage.identity==2,"fresh ray opens correct chest")
	adapter.update(game,0.001);check(not game.player_hud.interaction_hint.visible,"opened inventory hides prompt")
	game.storage.close();game.free();await process_frame
	print("BUILDING_INTERACTION_HINT failures=",failures);quit(1 if failures else 0)
