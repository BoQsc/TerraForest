# SPDX-License-Identifier: 0BSD
extends RefCounted
# Baked modular models; native collections own placement, damage and persistence.
const PARTS:={"straight": "Straight mine rail · 4 m", "short": "Short mine rail · 2 m", "curve": "Mine rail bend · 90°", "eighth": "Mine rail bend · 45°", "turnout": "Mine rail turnout"}
const PREFIX:="mining/rail_"
static func key(part:String)->String:return PREFIX+part+"/v1"
static func mesh(part:String)->Mesh:return load("res://addons/structures/prefabs/mine_rail_"+part+".res")
static func recipe(part:String)->PackedInt64Array:return PackedInt64Array([102,2 if part=="short" else 4,104,2 if part=="short" else 4])
static func register(world:Node3D)->Array[Dictionary]:
	var entries:Array[Dictionary]=[]
	for part:String in PARTS:
		var asset:=mesh(part)
		if asset==null:return []
		var collection:Node3D=world.register_model(key(part),asset)
		if collection==null:return []
		var parts:Array[AABB]=[]
		for bounds:AABB in asset.get_meta("collision_parts"):parts.append(bounds)
		if not collection.configure_compound_collision(parts,64,256,8,1024,32):return []
		entries.append({"title":PARTS[part],"mesh":asset,"collection":collection,"scale":Vector3.ONE,"costs":recipe(part),"cost_label":"2 wood + 2 metal" if part=="short" else "4 wood + 4 metal"})
	return entries
