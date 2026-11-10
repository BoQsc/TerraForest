# SPDX-License-Identifier: 0BSD
extends RefCounted
## One inventory schema for carried items, containers and world drops.
const Objects=preload("res://addons/player_runtime/carried_object_catalog.gd")
const CATALOG: Dictionary={1:"Pickaxe",2:"Hatchet",3:"Repair hammer",4:"Assembly tool",5:"Shovel",6:"Wooden torch",7:"Carbine",8:"Ranger assault rifle",9:"PX9 Eclipse handgun"}
const MATERIALS: Dictionary={101:"Brick",102:"Wood",103:"Concrete",104:"Metal"}
const RESOURCES: Dictionary={201:"Stone",202:"Iron ore",203:"Copper ore",204:"Plant",205:"Grass clump",206:"White wildflower",207:"Golden wildflower",208:"Violet wildflower",209:"Low bush",210:"Dry twigs",211:"Topsoil",212:"Woody bush",213:"Lockpick",214:"Field manual",215:"Unsent letter",216:"Survey journal",217:"Tinned beans",218:"Trail bread",219:"Dried berries",220:"Coal",221:"Carbine cartridges",222:"Explosive barrel",223:"Ranger cartridges",224:"Metal offcuts",225:"Cloth scraps",226:"Copper wire",227:"Loose fasteners",228:"PX9 cartridges",301:"Woven hood",302:"Woven vest",303:"Woven footwraps",304:"Trail hat",305:"Trail jerkin",306:"Trail boots",401:"Water bucket",402:"Water bucket",403:"Water bucket",404:"Water bucket",405:"Water bucket",406:"Water bucket",407:"Water bucket",408:"Water bucket",409:"Water bucket",410:"Water bucket",411:"Water bucket",501:"Vehicle",601:"Coins",701:"Wooden table",702:"Wooden chair",703:"Wooden shelf",704:"Wooden storage chest",705:"Wooden ladder",706:"Wooden fence",707:"Wood framed window"}
const KEYWORDS: Dictionary={
	1:["tool","tools","mining","mine","pick","stone","rock"],
	2:["tool","tools","axe","hatchet","wood","woodcutting","logging","chop"],
	3:["tool","tools","hammer","repair","fix","build","construction"],
	4:["tool","tools","assembly","build","placement","construction"],
	5:["tool","tools","shovel","dig","dirt","soil","earth"],
	6:["tool","tools","torch","light","fire","night","illumination"],
	7:["weapon","weapons","gun","firearm","rifle","carbine","shoot"],
	8:["weapon","weapons","gun","firearm","rifle","assault","ranger","automatic","shoot"],
	9:["weapon","pistol","handgun","px9","eclipse","firearm","shoot"],
	228:["ammo","ammunition","pistol","handgun","px9","cartridges"],
	101:["material","materials","building","block","brick","masonry","construction"],
	102:["material","materials","building","wood","timber","plank","construction"],
	103:["material","materials","building","concrete","cement","construction"],
	104:["material","materials","building","metal","steel","construction"],
	201:["resource","resources","stone","rock","mining","material"],
	202:["resource","resources","iron","ore","mining","metal"],
	203:["resource","resources","copper","ore","mining","metal","wire"],
	204:["resource","resources","plant","fiber","fibre","forage","crafting"],
	205:["resource","resources","grass","fiber","fibre","forage","crafting"],
	206:["resource","flower","white","wildflower","plant","forage"],
	207:["resource","flower","golden","wildflower","plant","forage"],
	208:["resource","flower","violet","wildflower","plant","forage"],
	209:["resource","bush","low","forage","plant"],
	210:["resource","twigs","twig","sticks","wood","kindling","fire"],
	211:["resource","topsoil","soil","dirt","earth","farming","terrain"],
	212:["resource","woody","bush","wood","forage","plant"],
	213:["tool","lockpick","lock","pick","thief","stealth"],
	214:["book","manual","read","guide","field","paper","document"],
	215:["letter","paper","note","write","document","unsent"],
	216:["book","journal","read","survey","paper","document"],
	217:["food","eat","beans","tin","can","ration","consume"],
	218:["food","eat","bread","trail","ration","consume"],
	219:["food","eat","berries","berry","dried","forage","consume"],
	220:["resource","coal","fuel","fire","ore","mining"],
	221:["ammo","ammunition","round","rounds","bullet","bullets","cartridge","cartridges","carbine","rifle","weapon"],
	222:["explosive","barrel","bomb","blast","hazard"],
	223:["ammo","ammunition","round","rounds","bullet","bullets","cartridge","cartridges","ranger","rifle","assault","weapon"],
	224:["resource","metal","scrap","offcuts","steel","crafting"],
	225:["resource","cloth","fabric","scraps","textile","crafting"],
	226:["resource","copper","wire","crafting","metal"],
	227:["resource","fasteners","fastener","nails","screws","hardware","crafting"],
	301:["clothing","wearable","hood","hat","head","armor"],
	302:["clothing","wearable","vest","armor","torso"],
	303:["clothing","wearable","footwraps","feet","boots"],
	304:["clothing","wearable","trail","hat","head"],
	305:["clothing","wearable","trail","jerkin","armor","torso"],
	306:["clothing","wearable","trail","boots","feet"],
	401:["water","bucket","container","liquid","drink"],402:["water","bucket","container","liquid","drink"],
	403:["water","bucket","container","liquid","drink"],404:["water","bucket","container","liquid","drink"],
	405:["water","bucket","container","liquid","drink"],406:["water","bucket","container","liquid","drink"],
	407:["water","bucket","container","liquid","drink"],408:["water","bucket","container","liquid","drink"],
	409:["water","bucket","container","liquid","drink"],410:["water","bucket","container","liquid","drink"],
	411:["water","bucket","container","liquid","drink"],
	501:["vehicle","car","drive","transport","truck"],
	601:["coins","coin","money","currency","cash"]
}

static func names() -> Dictionary:
	var result:=CATALOG.duplicate()
	result.merge(MATERIALS);result.merge(RESOURCES)
	return result

static func item_name(item:int)->String:
	return CATALOG.get(item,MATERIALS.get(item,RESOURCES.get(item,"Item %d"%item)))

static func search_text(item:int)->String:
	var text:=item_name(item).to_lower()+" "+str(item)
	if Objects.ITEMS.has(item):text+=" object furniture place placement"
	for keyword in KEYWORDS.get(item,[]):
		text+=" "+str(keyword).to_lower()
	return text

static func matches(item:int,query:String)->bool:
	var clean:=query.strip_edges().to_lower()
	if clean.is_empty():return true
	var haystack:=search_text(item)
	for term in clean.split(" ",false):
		if not haystack.contains(term):return false
	return true

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
