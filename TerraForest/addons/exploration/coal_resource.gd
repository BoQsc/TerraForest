# SPDX-License-Identifier: 0BSD
extends RefCounted
const KEY:="resources/coal_heap/v1"
const ITEM:=220
static func mesh()->Mesh:return load("res://addons/structures/prefabs/coal_heap.res")
static func register(world:Node3D)->bool:
	var collection:Node3D=world.register_model(KEY,mesh())
	return collection!=null and collection.configure_collision(AABB(Vector3(-.65,0,-.55),Vector3(1.3,.55,1.1)),64,128,8)
