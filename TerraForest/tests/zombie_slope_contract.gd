# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var active:=false
var encounter:Node3D
var player:CharacterBody3D
func _initialize()->void:run.call_deferred()
func tick()->void:
	if active:encounter.update(1.0/60,player.position,true)
func box(scene:Node3D,pose:Transform3D,size:Vector3)->void:
	var body:=StaticBody3D.new();body.transform=pose
	var shape:=BoxShape3D.new();shape.size=size;var collision:=CollisionShape3D.new();collision.shape=shape;body.add_child(collision);scene.add_child(body)
func run()->void:
	physics_frame.connect(tick)
	for angle in [32.0,46.0]:
		var scene:=Node3D.new();root.add_child(scene)
		var basis:=Basis(Vector3.BACK,deg_to_rad(angle))
		box(scene,Transform3D(Basis.IDENTITY,Vector3(-1,-.5,0)),Vector3(4,1,6))
		box(scene,Transform3D(basis,basis*Vector3(4,-.25,0)),Vector3(8,.5,4))
		player=CharacterBody3D.new();player.collision_layer=2;scene.add_child(player)
		player.position=Vector3(5,5*tan(deg_to_rad(angle))+.04,0)
		var collision:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8;collision.shape=capsule;collision.position.y=.9;player.add_child(collision)
		var target:=preload("res://addons/characters/runtime/zombie_target.gd").new();player.add_child(target)
		encounter=preload("res://addons/characters/runtime/zombie_world.gd").new();scene.add_child(encounter);encounter.enabled=true;encounter.target=target;encounter.readiness=func(_b:AABB):return true;encounter.population_enabled=false
		await physics_frame;await physics_frame
		encounter.force_pursuit=true # Physical slope capability, independent of perception.
		var zombie:CharacterBody3D=encounter.spawn_at(Vector3(-1,0,0));active=true
		for step in 1200:
			await physics_frame
			if target.damage_received>0 or encounter.navigator.status(zombie.get_instance_id()).state in ["blocked","search_limit"]:break
		var state:Dictionary=encounter.navigator.status(zombie.get_instance_id())
		var passed:bool=target.damage_received>0 and zombie.position.y>2 if angle==32 else target.damage_received==0 and zombie.position.x<.5 and state.state in ["blocked","search_limit"]
		print(("PASS " if passed else "FAIL "),"standing slope ",angle," position=",zombie.position," route=",JSON.stringify(state))
		if not passed:failures+=1
		active=false;encounter.clear();scene.free();await process_frame
	print("ZOMBIE_SLOPE_CONTRACT failures=",failures);quit(1 if failures else 0)
