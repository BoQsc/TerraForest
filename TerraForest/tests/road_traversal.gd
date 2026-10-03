# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var core: RefCounted=ClassDB.instantiate("TerrainCore")
	core.execute(Codec.command(6,[1703,2]))
	core.execute(Codec.brush(Vector3(416,184,400),Vector3(416,184,400),8,1,true,1))
	check(Codec.reply_ok(core.execute(Codec.road_bed(Vector3(400,180,400),Vector3(432,184,400),3,4,6))),"graded road cut constructed through solid hill")
	var epoch: int=core.execute(Codec.command(13)).decode_u32(12)
	var faces:=PackedVector3Array()
	for x in [400,416]:
		for z in [384,400]:
			var decoded: Dictionary=Codec.decode_mesh(core.build_owned_region(x,z,16,1,160,192,epoch))
			if decoded.has("error"): check(false,str(decoded));quit(1);return
			faces.append_array(decoded.faces)
	check(not faces.is_empty(),"native terrain collision triangles produced")
	var body:=StaticBody3D.new();body.collision_layer=1
	var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces)
	var collider:=CollisionShape3D.new();collider.shape=shape;body.add_child(collider);root.add_child(body)
	var player:=CharacterBody3D.new();player.collision_mask=1;player.floor_snap_length=0.35
	player.floor_max_angle=deg_to_rad(48);player.floor_constant_speed=true;player.safe_margin=0.01
	var capsule:=CapsuleShape3D.new();capsule.radius=0.34;capsule.height=1.8
	var collision:=CollisionShape3D.new();collision.shape=capsule;collision.position.y=0.9;player.add_child(collision);root.add_child(player)
	player.position=Vector3(410,181.35,400)
	var movement: RefCounted=ClassDB.instantiate("NativePlayerMovement")
	var min_height:=1000.0;var max_height:=-1000.0;var grounded_ticks:=0
	for tick in 160:
		await physics_frame
		var direction:=Vector3.RIGHT if tick>=20 and player.position.x<422 else Vector3.ZERO
		player.velocity=movement.walking_velocity(direction,player.velocity,1.0/60,false,player.is_on_floor(),false)
		movement.move_grounded(player,1.0/60)
		if tick>=20:
			min_height=minf(min_height,player.position.y);max_height=maxf(max_height,player.position.y)
			if player.is_on_floor(): grounded_ticks+=1
	print("TRAVERSAL ",{"position":player.position,"min_height":min_height,"max_height":max_height,"grounded_ticks":grounded_ticks})
	check(player.position.x>=421.5 and absf(player.position.z-400)<0.1,"capsule traverses graded cut across native mesh boundary")
	check(min_height>180.5 and max_height<183.5 and grounded_ticks>=130,"capsule remains supported without falling or jumping")
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(416,183,400),Vector3(416,179,400),1,[player.get_rid()])
	var hit:=root.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and absf(hit.position.y-182)<0.15,"native collision follows road grade at shared chunk edge")
	grounded_ticks=0
	for tick in 140:
		await physics_frame
		player.velocity=movement.walking_velocity(Vector3.LEFT if player.position.x>410 else Vector3.ZERO,player.velocity,1.0/60,false,player.is_on_floor(),false)
		movement.move_grounded(player,1.0/60)
		if player.is_on_floor(): grounded_ticks+=1
	check(player.position.x<=410.2 and player.position.y>181 and player.position.y<181.5 and grounded_ticks>=130,"capsule descends cut and remains supported across boundary")
	player.free();body.free();quit(1 if failures else 0)
