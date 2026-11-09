# SPDX-License-Identifier: 0BSD
extends RefCounted
## One finite merchant. Quotes are fixed here; UI supplies only item/quantity.
const CURRENCY := 601
const Durability=preload("res://addons/player_runtime/durability_catalog.gd")
const GOODS := {
	101: ["Brick", 5, 2, 160], 102: ["Wood", 4, 2, 200],
	103: ["Concrete", 6, 3, 120], 104: ["Metal", 12, 6, 60],
	201: ["Stone", 3, 1, 120], 202: ["Iron ore", 8, 4, 50],
	203: ["Copper ore", 10, 5, 40], 210: ["Dry twigs", 2, 1, 80],
	213: ["Lockpick", 8, 3, 24],
	224: ["Metal offcuts",3,1,8],225: ["Cloth scraps",2,1,12],
	226: ["Copper wire",4,2,8],227: ["Loose fasteners",2,1,12],
	214: ["Field manual", 30, 10, 4], 215: ["Unsent letter", 8, 2, 6], 216: ["Survey journal", 24, 8, 4],
	217: ["Tinned beans", 12, 4, 16], 218: ["Trail bread", 8, 3, 24], 219: ["Dried berries", 5, 2, 24],
	# Every inventory item is represented here. Appended entries keep the original
	# stock listing indices stable for existing tests and saved UI expectations.
	1: ["Pickaxe", 18, 7, 0], 2: ["Hatchet", 15, 6, 0], 3: ["Repair hammer", 16, 6, 0],
	4: ["Assembly tool", 15, 6, 0], 5: ["Shovel", 16, 6, 0], 6: ["Wooden torch", 4, 1, 0],
	7: ["Carbine", 70, 25, 0], 8: ["Ranger assault rifle", 120, 45, 0], 9: ["PX9 Eclipse handgun", 85, 30, 0], 228: ["PX9 cartridges", 2, 1, 0],
	204: ["Plant", 2, 1, 0], 205: ["Grass clump", 1, 1, 0],
	206: ["White wildflower", 2, 1, 0], 207: ["Golden wildflower", 3, 1, 0],
	208: ["Violet wildflower", 2, 1, 0], 209: ["Low bush", 2, 1, 0],
	211: ["Topsoil", 2, 1, 0], 212: ["Woody bush", 2, 1, 0],
	220: ["Coal", 10, 5, 0], 221: ["Carbine cartridges", 2, 1, 0],
	222: ["Explosive barrel", 40, 15, 0], 223: ["Ranger cartridges", 3, 1, 0],
	301: ["Woven hood", 12, 4, 0], 302: ["Woven vest", 18, 6, 0],
	303: ["Woven footwraps", 10, 3, 0], 304: ["Trail hat", 14, 5, 0],
	305: ["Trail jerkin", 22, 7, 0], 306: ["Trail boots", 18, 6, 0],
	401: ["Water bucket · 0 L", 6, 2, 0], 402: ["Water bucket · 1 L", 6, 2, 0],
	403: ["Water bucket · 2 L", 6, 2, 0], 404: ["Water bucket · 3 L", 6, 2, 0],
	405: ["Water bucket · 4 L", 6, 2, 0], 406: ["Water bucket · 5 L", 6, 2, 0],
	407: ["Water bucket · 6 L", 6, 2, 0], 408: ["Water bucket · 7 L", 6, 2, 0],
	409: ["Water bucket · 8 L", 6, 2, 0], 410: ["Water bucket · 9 L", 6, 2, 0],
	411: ["Water bucket · 10 L", 6, 2, 0],
	501: ["Vehicle", 200, 80, 0]
}
var stock: RefCounted
var saved_stock: RefCounted

static func stack_limit(item:int)->int:
	if item==CURRENCY:return 1000000
	if item>=1 and item<=8:return 1
	if item>=301:return 1
	return 999

static func durable_limit(item:int)->int:
	if item==501:return int(Durability.WORLD.vehicle)
	return int(Durability.TOOLS.get(item,0))

static func metadata_item(item:int)->bool:
	return durable_limit(item)>0 or (item>=401 and item<=411)

static func name_of(item:int)->String:
	return str(GOODS[item][0]) if GOODS.has(item) else "Item %d"%item

static func price(item:int,buying:bool)->int:
	if not GOODS.has(item):return 0
	return int(GOODS[item][1] if buying else GOODS[item][2])

static func register_currency(inventory: RefCounted) -> bool:
	return inventory.has_item(CURRENCY) or inventory.register_item(CURRENCY, 1000000)

static func make_inventory() -> RefCounted:
	var result: RefCounted = ClassDB.instantiate("NativePlayerInventory")
	for id: int in GOODS:
		result.register_item(id,stack_limit(id))
		var maximum:=durable_limit(id)
		if maximum>0:result.register_durable(id,maximum)
	result.register_item(CURRENCY, stack_limit(CURRENCY))
	return result

func _init() -> void:
	stock = make_inventory()
	var grants := PackedInt64Array([CURRENCY, 2400])
	for id: int in GOODS:
		var amount:int=int(GOODS[id][3])
		if amount>0:grants.append_array(PackedInt64Array([id, amount]))
	stock.grant_items(grants, stock.snapshot().revision)
	saved_stock=ClassDB.instantiate("NativeTraderStock")
	var additions:=PackedInt64Array()
	for identity:int in range(214,220):additions.append_array(PackedInt64Array([identity,GOODS[identity][3]]))
	if not saved_stock.configure(stock,additions):saved_stock=null

func register_persistence(persistence: RefCounted) -> bool:
	return saved_stock!=null and persistence.register_component("trader_civic_01", saved_stock.capture_storage_snapshot, saved_stock.restore_storage_snapshot, saved_stock, saved_stock.capture_storage_snapshot())

func exchange(player: RefCounted, item: int, quantity: int, buying: bool, player_revision: int, stock_revision: int, slot:int=-1) -> Dictionary:
	if not GOODS.has(item) or quantity < 1 or quantity > 999:
		return {"ok":false, "reason":"invalid_offer"}
	if metadata_item(item):
		if quantity!=1:return {"ok":false,"reason":"invalid_offer"}
		return _exchange_metadata(player,item,buying,player_revision,stock_revision,slot)
	var price: int = GOODS[item][1 if buying else 2] * quantity
	var money := PackedInt64Array([CURRENCY, price])
	var goods := PackedInt64Array([item, quantity])
	var result:Dictionary=player.exchange_with(stock, money if buying else goods, goods if buying else money, player_revision, stock_revision)
	if result.ok and saved_stock!=null:saved_stock.flush_pending()
	return result

# Native commodity exchange rejects wear and water. Move those slots intact and
# settle the coins in a second atomic transfer; every precondition is checked
# first, and a rejected settlement returns the exact slot to its owner.
func _exchange_metadata(player:RefCounted,item:int,buying:bool,expected_player:int,expected_stock:int,slot:int)->Dictionary:
	var unit:int=price(item,buying)
	if unit<=0:return {"ok":false,"reason":"invalid_offer"}
	if buying:
		if count(stock,item)<1:return {"ok":false,"reason":"insufficient_items"}
		if count(player,CURRENCY)<unit:return {"ok":false,"reason":"insufficient_items"}
		var source:=_first_slot(stock.snapshot(),item)
		var destination:=_first_empty(player.snapshot())
		if source<0:return {"ok":false,"reason":"insufficient_items"}
		if destination<0:return {"ok":false,"reason":"full"}
		var moved:Dictionary=stock.transfer_to(player,source,1,expected_stock,expected_player)
		if not moved.ok:return moved
		var paid:Dictionary=player.transfer_items_to(stock,PackedInt64Array([CURRENCY,unit]),player.snapshot().revision,stock.snapshot().revision)
		if not paid.ok:
			player.transfer_to(stock,destination,1,player.snapshot().revision,stock.snapshot().revision)
			return {"ok":false,"reason":"peer_rejected"}
		if saved_stock!=null:saved_stock.flush_pending()
		return {"ok":true,"revision":player.snapshot().revision}
	if count(player,item)<1:return {"ok":false,"reason":"insufficient_items"}
	if count(stock,CURRENCY)<unit:return {"ok":false,"reason":"peer_rejected"}
	var source:=slot
	if source<0 or source>=32 or int(player.snapshot().slots[source].item)!=item or int(player.snapshot().slots[source].count)<1:
		source=_first_slot(player.snapshot(),item)
	var destination:=_first_empty(stock.snapshot())
	if source<0:return {"ok":false,"reason":"insufficient_items"}
	if destination<0:return {"ok":false,"reason":"peer_rejected"}
	var moved:Dictionary=player.transfer_to(stock,source,1,expected_player,expected_stock)
	if not moved.ok:return moved
	var paid:Dictionary=stock.transfer_items_to(player,PackedInt64Array([CURRENCY,unit]),stock.snapshot().revision,player.snapshot().revision)
	if not paid.ok:
		stock.transfer_to(player,destination,1,stock.snapshot().revision,player.snapshot().revision)
		return {"ok":false,"reason":"peer_rejected"}
	if saved_stock!=null:saved_stock.flush_pending()
	return {"ok":true,"revision":player.snapshot().revision}

static func _first_slot(state:Dictionary,item:int)->int:
	for index in 32:
		var row:Dictionary=state.slots[index]
		if int(row.item)==item and int(row.count)>0:return index
	return -1

static func _first_empty(state:Dictionary)->int:
	for index in 32:
		if int(state.slots[index].count)==0:return index
	return -1

static func count(inventory: RefCounted, item: int) -> int:
	var total := 0
	for slot: Dictionary in inventory.snapshot().slots:
		if slot.item == item: total += slot.count
	return total
