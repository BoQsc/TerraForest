extends RefCounted

const Furniture = preload("res://addons/structures/furniture_catalog.gd")
const Workshop = preload("res://addons/structures/workshop_catalog.gd")

static func cells_of(asset: Resource) -> Dictionary:
	var cells: Dictionary = {}
	var records: PackedInt32Array = asset.get_records()
	for offset in range(0, records.size(), 4):
		cells[Vector3i(records[offset], records[offset+1], records[offset+2])] = records[offset+3]
	return cells

static func finish(source: Resource, cells: Dictionary, title: String) -> Resource:
	var records := PackedInt32Array()
	for cell: Vector3i in cells:
		records.append_array(PackedInt32Array([cell.x, cell.y, cell.z, cells[cell]]))
	var asset: Resource = ClassDB.instantiate("NativeBlockPrefab")
	if not asset.configure(records) or not asset.configure_model_attachments(source.get_model_attachments()): return null
	asset.resource_name = title
	asset.set_meta("review_only", true)
	asset.set_meta("review_revision", 1)
	asset.set_meta("source_design", source.resource_name)
	return asset

static func cottage(blocks: Node) -> Resource:
	var source: Resource = Furniture.enclosed_cottage()
	var cells := cells_of(source)
	for cell: Vector3i in cells.keys():
		if cell.y >= 6: cells.erase(cell)
	for column in range(-5, 6):
		var roof_height: int = 10 - absi(column)
		for row in range(-5, 6):
			cells[Vector3i(column, roof_height, row)] = blocks.encode_block(12 if column==0 else 4, 0 if column==0 else 3 if column<0 else 1, 1)
			if absi(row)==5:
				for height in range(6, roof_height):
					cells[Vector3i(column, height, row)] = blocks.encode_block(9, 12 if row>0 else 4, 1)
	for column in range(-3, 4):
		for row in range(-4, 5):
			cells[Vector3i(column, 5, row)] = blocks.encode_block(9, 0, 1)
	for column in [-1,1]: cells[Vector3i(column,0,7)] = blocks.encode_block(1,0,2)
	for height in range(1, 4):
		cells[Vector3i(-1, height, 7)] = blocks.encode_block(9, 20, 1)
		cells[Vector3i(1, height, 7)] = blocks.encode_block(9, 16, 1)
	cells[Vector3i(-1, 4, 7)] = blocks.encode_block(11, 2, 1)
	cells[Vector3i(0, 4, 7)] = blocks.encode_block(9, 8, 1)
	cells[Vector3i(1, 4, 7)] = blocks.encode_block(11, 0, 1)
	for column in range(-1, 2):
		for row in [6, 7]:
			cells[Vector3i(column, 5, row)] = blocks.encode_block(9, 0, 1)
	return finish(source, cells, "Cottage A / modular porch / review R1")

static func shop(blocks: Node) -> Resource:
	var source: Resource = Workshop.village_shop()
	var cells := cells_of(source)
	for cell: Vector3i in cells.keys():
		if cell.y >= 6: cells.erase(cell)
	for column in range(-7, 8):
		for row in range(-9, 10):
			var across: int = 7 - absi(column)
			var along: int = 9 - absi(row)
			var height: int = 5 + mini(across, along)
			var shape_id := 4
			var orientation := 3 if column<0 else 1
			if column==0 and along>=across:
				shape_id=12;orientation=0
			elif across==along:
				shape_id=13
				orientation=(0 if row<0 else 3) if column<0 else (1 if row<0 else 2)
			elif along<across:
				orientation=0 if row<0 else 2
			cells[Vector3i(column,height,row)] = blocks.encode_block(shape_id,orientation,1)
	for column in range(-5, 6):
		for row in range(-7, 8):
			var ceiling := Vector3i(column,5,row)
			if not cells.has(ceiling): cells[ceiling] = blocks.encode_block(9,0,1)
	cells[Vector3i(-1,4,-2)] = blocks.encode_block(11,2,1)
	cells[Vector3i(0,4,-2)] = blocks.encode_block(9,8,1)
	cells[Vector3i(1,4,-2)] = blocks.encode_block(11,0,1)
	return finish(source,cells,"Village shop B / hipped roof / review R1")

static func entries() -> Array[Dictionary]:
	return [
		{"title":"COTTAGE A", "original":Furniture.enclosed_cottage(), "candidate":load("res://reviews/modular_buildings/baked/cottage_a.tres"), "base":Vector3i.ZERO,
		"details":"Segmented timber porch arch  /  pointed ridge blocks  /  thin timber gables and ceiling",
		"eye":Vector3(17,12,24), "aim":Vector3(.5,4.7,.5), "inside":Vector3(.5,3.65,3.8), "inside_aim":Vector3(-.3,3.3,-2),
		"feature_eye":Vector3(5,5.5,13), "feature_aim":Vector3(.5,3.5,6), "remove":Vector3i(-1,4,7), "floor":2.0, "approach":10.0},
		{"title":"VILLAGE SHOP B", "original":Workshop.village_shop(), "candidate":load("res://reviews/modular_buildings/baked/shop_b.tres"), "base":Vector3i(0,0,-128),
		"details":"Four-sided hipped roof  /  individual hip-corner blocks  /  arched stores opening and ceiling",
		"eye":Vector3(23,16,30), "aim":Vector3(.5,5,.5), "inside":Vector3(.5,2.65,6.5), "inside_aim":Vector3(.5,3,-3.5),
		"feature_eye":Vector3(16,17,19), "feature_aim":Vector3(.5,8,.5), "remove":Vector3i(-1,4,-2), "floor":1.0, "approach":12.0}]
