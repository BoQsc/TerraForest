# SPDX-License-Identifier: 0BSD
extends RefCounted
## One finite merchant. Quotes are fixed here; UI supplies only item/quantity.
const CURRENCY := 601
const GOODS := {
	101: ["Brick", 5, 2, 160], 102: ["Wood", 4, 2, 200],
	103: ["Concrete", 6, 3, 120], 104: ["Metal", 12, 6, 60],
	201: ["Stone", 3, 1, 120], 202: ["Iron ore", 8, 4, 50],
	203: ["Copper ore", 10, 5, 40], 210: ["Dry twigs", 2, 1, 80],
	213: ["Lockpick", 8, 3, 24],
	224: ["Metal offcuts",3,1,8],225: ["Cloth scraps",2,1,12],
	226: ["Copper wire",4,2,8],227: ["Loose fasteners",2,1,12],
	214: ["Field manual", 30, 10, 4], 215: ["Unsent letter", 8, 2, 6], 216: ["Survey journal", 24, 8, 4],
	217: ["Tinned beans", 12, 4, 16], 218: ["Trail bread", 8, 3, 24], 219: ["Dried berries", 5, 2, 24]
}
var stock: RefCounted
var saved_stock: RefCounted

static func register_currency(inventory: RefCounted) -> bool:
	return inventory.has_item(CURRENCY) or inventory.register_item(CURRENCY, 1000000)

static func make_inventory() -> RefCounted:
	var result: RefCounted = ClassDB.instantiate("NativePlayerInventory")
	for id: int in GOODS: result.register_item(id, 999)
	result.register_item(CURRENCY, 1000000)
	return result

func _init() -> void:
	stock = make_inventory()
	var grants := PackedInt64Array([CURRENCY, 2400])
	for id: int in GOODS: grants.append_array(PackedInt64Array([id, GOODS[id][3]]))
	stock.grant_items(grants, stock.snapshot().revision)
	saved_stock=ClassDB.instantiate("NativeTraderStock")
	var additions:=PackedInt64Array()
	for identity:int in range(214,220):additions.append_array(PackedInt64Array([identity,GOODS[identity][3]]))
	if not saved_stock.configure(stock,additions):saved_stock=null

func register_persistence(persistence: RefCounted) -> bool:
	return saved_stock!=null and persistence.register_component("trader_civic_01", saved_stock.capture_storage_snapshot, saved_stock.restore_storage_snapshot, saved_stock, saved_stock.capture_storage_snapshot())

func exchange(player: RefCounted, item: int, quantity: int, buying: bool, player_revision: int, stock_revision: int) -> Dictionary:
	if not GOODS.has(item) or quantity < 1 or quantity > 999:
		return {"ok":false, "reason":"invalid_offer"}
	var price: int = GOODS[item][1 if buying else 2] * quantity
	var money := PackedInt64Array([CURRENCY, price])
	var goods := PackedInt64Array([item, quantity])
	var result:Dictionary=player.exchange_with(stock, money if buying else goods, goods if buying else money, player_revision, stock_revision)
	if result.ok:saved_stock.flush_pending()
	return result

static func count(inventory: RefCounted, item: int) -> int:
	var total := 0
	for slot: Dictionary in inventory.snapshot().slots:
		if slot.item == item: total += slot.count
	return total
