# SPDX-License-Identifier: 0BSD
extends RefCounted
func run(tree:SceneTree,game:Node,output:String)->void:
	var events:Array=[]
	var trace:Node=tree.root.get_node_or_null("WorldSession/FrameTrace")
	# Exercise normal damage, dismemberment and deferred corpse setup separately.
	# No densities, renderer settings, collision or simulation rates are changed.
	for index in 3:
		var candidates:Array=game.zombies.residents.filter(func(zombie:Node3D):return zombie.alive)
		candidates.sort_custom(func(a:Node3D,b:Node3D):return a.global_position.distance_squared_to(game.player.global_position)<b.global_position.distance_squared_to(game.player.global_position))
		if candidates.is_empty():break
		var zombie:Node3D=candidates[0]
		game.yaw=atan2(-(zombie.global_position-game.player.global_position).x,-(zombie.global_position-game.player.global_position).z)
		for action:String in ["hit","sever","kill"]:
			tree.label="combat_"+action
			if trace!=null:trace.mark(tree.label)
			var began:=Time.get_ticks_usec()
			zombie.receive_hit("forearm_l" if action=="sever" else "torso",180.0 if action=="kill" else 1.0,zombie.global_position+Vector3.UP,Vector3.ZERO,action=="sever","melee")
			events.append({"action":action,"us":Time.get_ticks_usec()-began,"at_us":began,"position":zombie.global_position,"alive":zombie.alive})
			await tree.wait_for(func():return false,2.5)
			if not is_instance_valid(zombie):break
	FileAccess.open(output.path_join("combat_probe.json"),FileAccess.WRITE).store_string(JSON.stringify({"events":events,"vehicle_install":game.world_vehicle.install_timings,"trader_anchor":game.trader.anchor,"trader_position":game.trader.ride.spawn_position()}))
	print("COMBAT_PROBE events=",events)
