# SPDX-License-Identifier: 0BSD
extends RefCounted
## One inventory schema for carried items, containers and world drops.
const CATALOG: Dictionary={1:"Pickaxe",2:"Hatchet",3:"Repair hammer",4:"Assembly tool",5:"Shovel",6:"Wooden torch",7:"Carbine",8:"Ranger assault rifle"}
const MATERIALS: Dictionary={101:"Brick",102:"Wood",103:"Concrete",104:"Metal"}
const RESOURCES: Dictionary={201:"Stone",202:"Iron ore",203:"Copper ore",204:"Plant",205:"Grass clump",206:"White wildflower",207:"Golden wildflower",208:"Violet wildflower",209:"Low bush",210:"Dry twigs",211:"Topsoil",212:"Woody bush",213:"Lockpick",214:"Field manual",215:"Unsent letter",216:"Survey journal",217:"Tinned beans",218:"Trail bread",219:"Dried berries",220:"Coal",221:"Carbine cartridges",222:"Explosive barrel",223:"Ranger cartridges",224:"Metal offcuts",225:"Cloth scraps",226:"Copper wire",227:"Loose fasteners",301:"Woven hood",302:"Woven vest",303:"Woven footwraps",304:"Trail hat",305:"Trail jerkin",306:"Trail boots",401:"Water bucket",402:"Water bucket",403:"Water bucket",404:"Water bucket",405:"Water bucket",406:"Water bucket",407:"Water bucket",408:"Water bucket",409:"Water bucket",410:"Water bucket",411:"Water bucket",501:"Vehicle",601:"Coins"}

static func names() -> Dictionary:
	var result:=CATALOG.duplicate()
	result.merge(MATERIALS);result.merge(RESOURCES)
	return result

static func item_name(item:int)->String:
	return CATALOG.get(item,MATERIALS.get(item,RESOURCES.get(item,"Item %d"%item)))

static func stack_limit(item:int)->int:
	if CATALOG.has(item):return 1
	if MATERIALS.has(item):return 999
	if RESOURCES.has(item):return 1000000 if item==601 else (1 if item>=301 else 999)
	return 0

static func create_inventory()->RefCounted:
	if not ClassDB.class_exists("NativePlayerInventory"):
		GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	if not ClassDB.class_exists("NativePlayerInventory"):return null
	var inventory:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	for item:int in names():
		if not inventory.register_item(item,stack_limit(item)):return null
		var maximum:int=preload("res://addons/player_runtime/durability_catalog.gd").TOOLS.get(item,0)
		if item==501:maximum=preload("res://addons/player_runtime/durability_catalog.gd").WORLD.vehicle
		if maximum>0 and not inventory.register_durable(item,maximum):return null
	return inventory
