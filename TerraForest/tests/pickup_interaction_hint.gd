# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func settle() -> void:
	for i in 12:await physics_frame;await process_frame
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"actual world loads"):await finish();return
	game.set_physics_process(false);game._clear_motion()
	var base: Vector3=game.player.position+Vector3(0,8,0)
	aim(base,base+Vector3(0,1.62,-2))
	var point:=base+Vector3(0,1.62,-1.5)
	var slot:=slot_of(1)
	check(game.player_hud.inventory.wear_tool(slot,7,game.player_hud.inventory.snapshot().revision).ok,"tool wear prepared")
	var dropped: Dictionary=game.pickups.drop_stack(game.player_hud.inventory,slot,game.player_hud.inventory.snapshot().revision,point,1)
	if not check(dropped.ok,"held tool dropped through inventory transaction"):await finish();return
	game.pickups.update_view(0,base,true);game.world_interaction.update(game,1.0)
	check(game.player_hud.interaction_hint.text=="E · Pick up Pickaxe","HUD names aimed dropped tool")
	var obstruction:=StaticBody3D.new();obstruction.collision_layer=4
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,2,0.1);collision.shape=box;obstruction.add_child(collision);game.add_child(obstruction)
	obstruction.global_position=base+Vector3(0,1.62,-0.8);await settle()
	game.app_focused=true;game.world_interaction.update(game,1.0)
	check(not game.player_hud.interaction_hint.visible,"vehicle-layer obstruction hides pickup prompt")
	use();check(game.pickups.stores[1].resolve_identity(dropped.id)>0,"E fallback also cannot collect through vehicle")
	obstruction.free();await settle();game.app_focused=true
	use()
	check(game.pickups.stores[1].resolve_identity(dropped.id)==0 and slot_of(1)>=0,"E transfers aimed tool and removes world record")
	check(game.player_hud.inventory.snapshot().slots[slot_of(1)].wear==7,"recovered tool retains exact wear")
	var ore: int=game.pickups.spawn(202,point)
	game.world_interaction.update(game,1.0)
	check(game.player_hud.interaction_hint.text=="E · Pick up Iron ore","HUD names ore model")
	var before:=amount(202);use()
	check(amount(202)==before+1 and game.pickups.stores[202].resolve_identity(ore)==0,"ore collection grants exact item")
	game.world_interaction.update(game,1.0)
	check(not game.player_hud.interaction_hint.visible,"collected pickup prompt clears")
	await finish()
