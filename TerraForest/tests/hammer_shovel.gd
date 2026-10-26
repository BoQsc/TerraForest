# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var impacts:Array=[]
var checks:=0
class SnapshotTerrain extends Node:
	var prepared_snapshot_components:Dictionary={}
	var snapshot_restore_ok:=true
func verify(ok:bool,label:String)->bool:
	checks+=1;return check(ok,label)
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(name+".png"))
func run()->void:
	evidence="res://reports/hammer_shovel/world";DirAccess.make_dir_recursive_absolute(evidence)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60
	game.player_view.settings_path="";root.add_child(game)
	if not verify(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,50),"playable temporary world ready"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.ground_enabled=false
	game.zombies.clear();game.zombies.population_enabled=false
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false)
	var hud=game.player_hud;var inventory:RefCounted=hud.inventory;var attack=game.world_attack
	verify(hud.CATALOG[3]=="Repair hammer" and hud.CATALOG[4]=="Assembly tool" and hud.CATALOG[5]=="Shovel","existing item IDs preserved; shovel is item 5")
	var initial:PackedByteArray=inventory.capture_storage_snapshot()
	var recipe:=-1
	for index in hud.Crafting.RECIPES.size():
		if hud.Crafting.RECIPES[index].outputs==[5,1]:recipe=index
	var wood:=amount(102);var metal:=amount(104)
	verify(hud.Crafting.craft(inventory,recipe,1,inventory.snapshot().revision).ok and amount(5)==1 and amount(102)==wood-2 and amount(104)==metal-2,"crafting makes one durable shovel for two wood and two metal")
	var crafted:PackedByteArray=inventory.capture_storage_snapshot()
	verify(inventory.restore_storage_snapshot(initial) and amount(5)==0,"old loadout without shovel restores without free grants")
	verify(inventory.restore_storage_snapshot(crafted) and amount(5)==1,"new shovel survives native inventory save/restore")
	hud.refresh();hud.equip_item(5)
	verify(game.equipped_tool==5 and not game.structure_mode and not game.model_tool.active and game.tool_view.attack_profile().clip=="FP_Shovel_Swing","shovel equips through the ordinary inventory path without editor controls")
	var slot:int=hud.active_slot
	inventory.wear_tool(slot,17,inventory.snapshot().revision)
	var point:Vector3=game.player.position+Vector3.UP*.3
	var dropped:Dictionary=game.pickups.drop_stack(inventory,slot,inventory.snapshot().revision,point,1)
	verify(dropped.ok and amount(5)==0,"shovel drops as a collectible native pickup")
	# Round-trip only the inventory/pickup providers. Other world components
	# use prepared native snapshots and cannot be restored from raw captures.
	var provider=preload("res://addons/world_runtime/world_persistence.gd").new()
	for name:String in ["player_loadout","pickups_5","pickup_stacks_5"]:
		var entry:Dictionary=game.persistence._providers[name]
		provider.register_component(name,entry.capture,entry.restore,entry.validator,entry.empty)
	var terrain:=SnapshotTerrain.new();root.add_child(terrain);provider._terrain=terrain
	var sections:Dictionary=provider._capture().sections
	verify(game.pickups.collect_near(point,inventory,func(_p):return true).ok and inventory.snapshot().slots[slot_of(5)].wear==17,"recollecting shovel preserves wear")
	provider._restore(sections,1);terrain.free()
	verify(amount(5)==0 and game.pickups.stores[5].statistics().active==1,"compound restore preserves dropped shovel ownership")
	verify(game.pickups.collect_near(point,inventory,func(_p):return true).ok and inventory.snapshot().slots[slot_of(5)].wear==17,"saved shovel pickup recollects once with its saved wear")
	hud.refresh()
	var base:=Vector3i(game.player.position.floor())+Vector3i(0,10,0)
	game.structures.blocks.set_focus(Vector3(base));game.structures.blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,33]))
	aim(Vector3(base)+Vector3(0,0,3),Vector3(base)+Vector3.ONE*.5)
	game.camera.global_position=Vector3(base)+Vector3(.5,.5,2.5);game.camera.look_at(Vector3(base)+Vector3.ONE*.5)
	for i in 4:await physics_frame
	hud.equip_item(3)
	verify(await wait_for(func():return attack.target().get("kind")=="block",5),"real block collider publishes before the hammer check")
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var key:String=attack.block_key(base)
	attack.durability.hit(key,60,40)
	var wear:int=inventory.snapshot().slots[hud.active_slot].wear
	attack.impact_resolved.connect(func(identity:int,accepted:bool):impacts.append({"identity":identity,"accepted":accepted,"time":game.tool_view.human.animation_player.current_animation_position}))
	attack.next_attack=0
	print("HAMMER_INPUT ",JSON.stringify({"admitted":game._model_edit_available(),"focused":game.app_focused,"mouse":Input.mouse_mode,"ui":game.session_menu.visible_ui(),"item":game.equipped_tool,"visible":game.tool_view.is_visible_in_tree(),"profile":game.tool_view.attack_profile(),"remaining":game.tool_view.human.action_remaining,"target":attack.target()}))
	verify(attack.attack(true) and attack.durability.damage(key,60)==40,"hammer repair windup does not mutate target")
	verify(await preload("res://tests/swing_driver.gd").finish(game) and attack.durability.damage(key,60)==15 and inventory.snapshot().slots[hud.active_slot].wear==wear+1,"Blender hammer repairs exactly once and consumes one wear point")
	print("HAMMER_RESULT ",JSON.stringify({"impacts":impacts,"target":attack.target(),"damage":attack.durability.damage(key,60),"focused":game.app_focused,"mouse":Input.mouse_mode}))
	verify(impacts.size()==1 and impacts[0].accepted and is_equal_approx(impacts[0].time,28.0/60.0),"hammer repair uses Blender contact frame 28")
	await capture("hammer_repair")
	game.structures.blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,0]))
	# Real terrain plus real mouse input; no mocked ray or mutation adapter.
	var origin:Vector3=point+Vector3(15,50,15)
	var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin-Vector3.UP*200,1))
	if verify(not hit.is_empty(),"loaded nearby terrain available for shovel"):
		hud.equip_item(5);game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		game.player.position=hit.position+Vector3.UP*.2
		game.camera.global_position=hit.position+Vector3.UP*2;game.camera.look_at(hit.position,Vector3.FORWARD)
		verify(attack.target().get("kind")=="terrain","shovel aims at real terrain within normal reach")
		var revision:int=game.terrain.density_revision
		wear=inventory.snapshot().slots[hud.active_slot].wear
		var count:=impacts.size();attack.next_attack=0
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
		Input.parse_input_event(click);Input.flush_buffered_events();await process_frame;game._update_edit(.1)
		click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT
		Input.parse_input_event(click);Input.flush_buffered_events()
		verify(not attack.pending.is_empty() and game.terrain.density_revision==revision,"mouse starts shovel windup before excavation")
		verify(await wait_for(func():return attack.pending.is_empty() and not game.terrain.pending_edit,20) and game.terrain.density_revision>revision and not game.mining_rewards.failed,"shovel contact publishes real native excavation and mining rewards")
		verify(impacts.size()==count+1 and impacts[-1].accepted and is_equal_approx(impacts[-1].time,34.0/60.0) and inventory.snapshot().slots[hud.active_slot].wear==wear+1,"shovel excavation uses frame 34 and consumes wear once")
		await capture("shovel_excavation")
	verify(preload("res://addons/player_runtime/item_icons.gd").texture(5)!=null and load("res://addons/player_runtime/art/drops/5.res")!=null,"shovel has a static inventory icon and baked world pickup mesh")
	for label:String in ["Hammer","Shovel"]:
		var triangles:=0;var mapped_steel:=false
		for mesh:MeshInstance3D in game.tool_view.human.meshes:
			if not label in String(mesh.name):continue
			for surface in mesh.mesh.get_surface_count():
				triangles+=mesh.mesh.surface_get_array_index_len(surface)/3
				var material:StandardMaterial3D=mesh.mesh.surface_get_material(surface)
				if material.metallic>.9 and material.albedo_texture!=null and material.roughness_texture!=null and material.normal_enabled and material.normal_texture!=null:mapped_steel=true
		verify(triangles>10000 and mapped_steel,label+" has dense geometry and embedded PBR base color, roughness and normal maps")
	await finish()
func finish()->void:
	game.shutdown_requested=true
	verify(await game.terrain.shutdown_after_edits(),"temporary compound world closes consistently")
	game.free();await process_frame;await process_frame
	print("HAMMER_SHOVEL checks=",checks," failures=",failures);quit(1 if failures else 0)
