# SPDX-License-Identifier: 0BSD
extends RefCounted
var game:Node
var menu:CanvasLayer
var status:Label
var entries:Dictionary={}
var last_spawn:CharacterBody3D
func build(host:Node,session:CanvasLayer,parent:VBoxContainer)->void:
	game=host;menu=session
	menu.label(parent,"Dev Spawner").add_theme_font_size_override("font_size",24)
	menu.label(parent,"Spawn living entities on clear, loaded ground nearby. Spawns are real world residents and are saved normally. Vehicles, tools and materials are in Dev Bag.")
	entries["zombie"]=menu.button(parent,"Spawn zombie nearby",spawn_zombie)
	menu.label(parent,"Zombies use normal awareness, combat, anatomy and corpse storage. Spawning enables their simulation for this session. The existing six-active-zombie budget still applies; no inhabitants are silently removed to make room.")
	status=menu.label(parent,"");refresh()
func refresh()->void:
	status.text="Active zombies: %d / %d · Resume to let entities move and react"%[game.zombies.residents.size(),game.zombies.LIMIT]
func spawn_zombie()->void:
	last_spawn=null
	if game.loading_active or game.shutdown_requested or game.terrain.pending_edit or game.world_vehicle.driving:
		menu.message.text="Spawn on foot after the current world edit or loading finishes.";return
	var host:Node3D=game.zombies
	if host.residents.size()>=host.LIMIT:
		menu.message.text="All six active zombie slots are occupied. Move away from this group or defeat a zombie before spawning another.";refresh();return
	var forward:Vector3=-game.player.global_basis.z;forward.y=0;forward=forward.normalized()
	var point:=Vector3.INF
	for distance:float in [4.0,6.0,8.0]:
		for angle:float in [0.0,-0.5,0.5,-1.0,1.0]:
			point=host.supported_point(game.player.global_position+forward.rotated(Vector3.UP,angle)*distance)
			if point.is_finite():break
		if point.is_finite():break
	if not point.is_finite():menu.message.text="No clear, loaded ground nearby. Move to an open, dry area and try again.";return
	var population:RefCounted=host.population
	if population==null or not population.store.initialize(game.terrain.backend.world_seed,game._initial_generation_spawn):
		menu.message.text="World population storage is unavailable.";return
	if population.store.statistics().slots>=2756:menu.message.text="This world has reached its 256 additional developer-zombie limit.";return
	var was_enabled:bool=host.enabled;host.enabled=true
	var zombie:CharacterBody3D=host.spawn_at(point)
	if zombie==null:host.enabled=was_enabled;menu.message.text="Zombie placement changed; try again on clear ground.";return
	var identity:int=population.store.add_resident(zombie.global_position,zombie.global_rotation.y,zombie.anatomy.capture_vitals())
	if identity==0:
		host._retire(host.residents.find(zombie));host.enabled=was_enabled;menu.message.text="Could not save the new zombie; no entity was kept.";return
	zombie.set_meta("world_zombie_id",identity);zombie.died.connect(func():population.sync(zombie))
	zombie.process_mode=Node.PROCESS_MODE_DISABLED;zombie.set_behavior(false)
	game.player.collision_mask|=host.CHARACTER_LAYER;game.terrain.changed_since_save=true
	last_spawn=zombie;menu.message.text="Zombie spawned nearby · Resume to play · Save world to keep it";refresh()
