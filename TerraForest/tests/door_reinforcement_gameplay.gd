# SPDX-License-Identifier: 0BSD
extends SceneTree

class Host extends Node3D:
	var structures=preload("res://addons/structures/structures_world.gd").new()
	var persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
	var doors=preload("res://addons/structures/door_interaction.gd").new()
	var player_hud=preload("res://addons/player_runtime/player_hud.gd").new()
	var camera:=Camera3D.new()
	var player:=CharacterBody3D.new()
	var storage:Dictionary={"collection":null}
	var combat:Dictionary={"Barrel":{"KEY":"combat/explosive_barrel/v1"}}
	var terrain:Dictionary={"changed_since_save":false}
	var equipped_tool:=2
	var notice:=""
	func _model_edit_available()->bool:return true
	func _show_lake_notice(text:String)->void:notice=text

var checks:=0
var failures:=0

func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func settle()->void:
	for frame in 12:await physics_frame;await process_frame

func ray()->Dictionary:
	return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(.5,1,2),Vector3(.5,1,-2),2))

func run()->void:
	var game:=Host.new();root.add_child(game)
	for child:Node in [game.structures,game.camera,game.player,game.player_hud]:game.add_child(child)
	var door:Dictionary=preload("res://addons/structures/door_catalog.gd").register(game.structures)
	check(game.doors.prepare(game),"actual door adapters and compound persistence prepare")
	game.doors.set_physics_process(false);game.player_hud.equip(1)
	var entry:Dictionary=game.doors.types[door.id]
	var batch:Node3D=door.collection
	var closed:=PackedFloat32Array([1,0,0,0,0,door.scale.y,0,0,0,0,1,0])
	check(batch.upsert_instances(PackedInt64Array([7]),closed) and entry.locks.seed(7,180,1703),"locked production door placed")
	batch.set_collision_focus(Vector3.ZERO);await settle()
	var hit:=ray()
	check(not hit.is_empty() and "reinforced" in game.doors.describe(hit),"real physics picking identifies the reinforced door")
	check(game.doors.try_interact(hit) and not entry.state.is_open(7) and entry.locks.store.is_locked(7),"E without a pick leaves real entrance blocked")
	var attack=preload("res://addons/player_runtime/world_attack.gd").new();attack.game=game;attack.durability=ClassDB.instantiate("NativeWorldDurability")
	var before:PackedByteArray=attack.durability.capture_storage_snapshot()
	var inventory:RefCounted=game.player_hud.inventory
	var wear:int=inventory.snapshot().slots[1].wear
	var target:Dictionary={"kind":"model","key":"model:"+door.id+":7","id":7,"collection":batch,"asset":door.id,"health":90,"material":"wood","name":"Wooden door"}
	for index in 6:
		check(attack.apply_target(target) and entry.locks.store.is_locked(7)==(index<5),"weapon contact damages reinforcement: hit %d"%(index+1))
	await settle()
	check(batch.get_instance(7)==closed and attack.durability.capture_storage_snapshot()==before and not target.destroyed,"breaking reinforcement preserves the undamaged closed door")
	check(inventory.snapshot().slots[1].wear==wear+6 and game.terrain.changed_since_save and "Reinforcement broken" in game.notice,"entry costs tool wear and persists without opening a modal")
	check(entry.reinforcement.shown.is_empty() and not ray().is_empty(),"boards vanish while physical door collision stays")
	check(game.doors.try_interact(ray()),"next E starts ordinary door opening")
	for frame in 90:game.doors.update(1.0/60)
	await settle()
	check(entry.state.is_open(7) and ray().is_empty(),"opening clears the actual passage")
	entry.state.toggle(batch,7,AABB());await settle()
	check(entry.locks.seed(7,180,1703) and inventory.grant(213,64,inventory.snapshot().revision).ok,"second entry allows lockpicking")
	var attempts:=0
	while entry.locks.store.is_locked(7) and attempts<32:
		attempts+=1;game.doors.try_interact(ray())
	for frame in 90:game.doors.update(1.0/60)
	await settle()
	check(not entry.locks.store.is_locked(7) and entry.state.is_open(7) and entry.reinforcement.shown.is_empty() and ray().is_empty(),"successful E lockpick removes boards and opens the same native door")
	game.free()
	print("DOOR_REINFORCEMENT_GAMEPLAY checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
