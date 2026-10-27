extends RefCounted

const PATH := "res://reviews/modular_buildings/baked/large_house_c1.tres"
const STAIR_COLUMNS := [2, 3]
const STAIR_ROWS := [-4, -3, -2, -1]

static func build(blocks: Node) -> Resource:
	var cells := {}
	var attachments: Array = []
	for level in [-3, 1, 5]:
		for column in range(-5, 6):
			for row in range(-7, 8):
				if level != -3 and column in STAIR_COLUMNS and row in STAIR_ROWS:
					continue
				cells[Vector3i(column, level - 1, row)] = blocks.encode_block(8, 0, 2 if level == -3 else 1)
	for column in range(-5, 6):
		for row in range(-7, 8):
			if absi(column) != 5 and absi(row) != 7:
				continue
			for level in range(-3, 9):
				cells[Vector3i(column, level, row)] = blocks.encode_block(1, 0, 2 if level < 1 else 0)
	for level in [1, 5]:
		for row in [-7, 7]:
			for column in [-3, 2]:
				window(blocks, cells, attachments, Vector3i(column, level + 1, row), false)
		for row in [-4, 2]:
			window(blocks, cells, attachments, Vector3i(-5, level + 1, row), true)
			if level == 5 or row == -4:
				window(blocks, cells, attachments, Vector3i(5, level + 1, row), true)
		door(cells, attachments, Vector3i(0, level, 7), false)
	for level in [-3, 1, 5]:
		for row in range(-6, 7):
			for height in range(level, level + 4):
				cells[Vector3i(-1, height, row)] = blocks.encode_block(1, 0, 2 if level == -3 else 0)
		for row in [-2 if level == 5 else -4, 3]:
			door(cells, attachments, Vector3i(-1, level, row), true)
		for column in range(-4, -1):
			for height in range(level, level + 4):
				cells[Vector3i(column, height, 0)] = blocks.encode_block(1, 0, 2 if level == -3 else 0)
	for base in [-3, 1]:
		for step in 4:
			for column in STAIR_COLUMNS:
				cells[Vector3i(column, base + step, STAIR_ROWS[step])] = blocks.encode_block(3, 0, 1)
	for level in [1, 5]:
		for row in STAIR_ROWS:
			cells[Vector3i(1, level, row)] = blocks.encode_block(9, 16, 1)
			cells[Vector3i(4, level, row)] = blocks.encode_block(9, 20, 1)
	for row in [-5, -4, 1, 2]:
		for column in [-4, -3]:
			cells[Vector3i(column, 5, row)] = blocks.encode_block(2, 0, 1)
	for column in [-4, -3]:
		cells[Vector3i(column, 5, -6)] = blocks.encode_block(9, 12, 1)
		cells[Vector3i(column, 5, 3)] = blocks.encode_block(9, 4, 1)
	for column in range(-4, 5):
		for row in range(-6, 7):
			cells[Vector3i(column, 9, row)] = blocks.encode_block(9, 0, 1)
	for column in range(-4, 3):
		for row in range(8, 11):
			cells[Vector3i(column, 5, row)] = blocks.encode_block(9, 0, 1)
		cells[Vector3i(column, 5, 11)] = blocks.encode_block(9, 4, 1)
	for row in range(8, 11):
		cells[Vector3i(-5, 5, row)] = blocks.encode_block(9, 16, 1)
		cells[Vector3i(3, 5, row)] = blocks.encode_block(9, 20, 1)
	for column in [-4, 2]:
		for level in range(1, 5):
			cells[Vector3i(column, level, 10)] = blocks.encode_block(5, 0, 1)
		cells[Vector3i(column, 0, 10)] = blocks.encode_block(1, 0, 2)
	for column in range(6, 13):
		for row in range(-2, 8):
			cells[Vector3i(column, 0, row)] = blocks.encode_block(8, 0, 2)
			cells[Vector3i(column, 5, row)] = blocks.encode_block(9, 0, 1)
			if column != 12 and row != -2 and row != 7:
				continue
			for level in range(1, 5):
				if row == 7 and column in range(7, 12) and level < 4:
					continue
				cells[Vector3i(column, level, row)] = blocks.encode_block(1, 0, 0)
	door(cells, attachments, Vector3i(5, 1, 3), true)
	window(blocks, cells, attachments, Vector3i(12, 2, 1), true)
	roof(blocks, cells, 0, 5, -7, 7, 14)
	roof(blocks, cells, 9, 3, -2, 7, 8)
	attach(attachments, "furniture/table/v1", Vector3(-3, 1, 3.7))
	attach(attachments, "furniture/chair/v1", Vector3(-3, 1, 5.2))
	attach(attachments, "furniture/shelf/v1", Vector3(-3, 1, -5.7), PI)
	attach(attachments, "storage/wooden_chest/v1", Vector3(-3, 1, -2))
	attach(attachments, "furniture/table/v1", Vector3(2, 5, 3.5))
	attach(attachments, "furniture/chair/v1", Vector3(2, 5, 5))
	attach(attachments, "furniture/shelf/v1", Vector3(-3, 5, 5.8))
	attach(attachments, "storage/wooden_chest/v1", Vector3(-3, 5, -2))
	attach(attachments, "furniture/table/v1", Vector3(3.5, 1, 4.5))
	attach(attachments, "furniture/shelf/v1", Vector3(3.5, 1, 6.2))
	attach(attachments, "furniture/table/v1", Vector3(-3, -3, 3.5))
	attach(attachments, "furniture/shelf/v1", Vector3(-3, -3, -5.7), PI)
	attach(attachments, "storage/wooden_chest/v1", Vector3(1, -3, 5.5))
	attach(attachments, "storage/wooden_chest/v1", Vector3(3, -3, 5.5))
	attach(attachments, "furniture/table/v1", Vector3(11.3, 1, .5), PI / 2)
	attach(attachments, "storage/wooden_chest/v1", Vector3(7, 1, .5))
	var records := PackedInt32Array()
	for cell: Vector3i in cells:
		records.append_array(PackedInt32Array([cell.x, cell.y, cell.z, cells[cell]]))
	var result: Resource = ClassDB.instantiate("NativeBlockPrefab")
	if not result.configure(records) or not result.configure_model_attachments(attachments):
		return null
	result.resource_name = "House C1 / two storeys, balcony, garage, basement / proposal"
	result.set_meta("review_only", true)
	result.set_meta("review_revision", 1)
	result.set_meta("finished_grade", 1.0)
	result.set_meta("basement_excavation", AABB(Vector3(-5, -4, -7), Vector3(11, 5, 15)))
	return result

static func door(cells: Dictionary, attachments: Array, origin: Vector3i, side: bool) -> void:
	for height in 3:
		cells.erase(origin + Vector3i(0, height, 0))
	var inward := side and origin.x < 0
	var position := Vector3(origin) + Vector3(.5 if side else 0, 0, 1 if inward else 0 if side else .5)
	var yaw: float = PI / 2 if inward else -PI / 2 if side else 0
	attachments.append({"model":"architecture/wooden_door/v1", "transform":Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1, 1.25, 1)), position)})

static func window(blocks: Node, cells: Dictionary, attachments: Array, origin: Vector3i, side: bool) -> void:
	for offset in 2:
		for height in 2:
			cells.erase(origin + Vector3i(0 if side else offset, height, offset if side else 0))
	var position := Vector3(origin) + Vector3(.5 if side else 1, 0, 1 if side else .5)
	attachments.append({"model":"architecture/wooden_window/v1", "transform":Transform3D(Basis(Vector3.UP, PI / 2 if side else 0), position)})
	for offset in 2:
		cells[origin + Vector3i(0 if side else offset, -1, offset if side else 0)] = blocks.encode_block(1, 0, 2)

static func roof(blocks: Node, cells: Dictionary, center: int, radius: int, back: int, front: int, peak: int) -> void:
	for column in range(center - radius, center + radius + 1):
		var height := peak - absi(column - center)
		for row in range(back - 1, front + 2):
			var cell := Vector3i(column, height, row)
			if row == back or row == front:
				for level in range(peak - radius, height):
					cells[Vector3i(column, level, row)] = blocks.encode_block(1, 0, 1)
				cells[cell] = blocks.encode_block(12 if column == center else 4, 0 if column == center else 3 if column < center else 1, 1)
			else:
				var rotation := 0 if column <= center else 2
				cells[cell] = blocks.encode_block(17 if column == center else 15, rotation, 1)
				if not cells.has(cell + Vector3i.DOWN):
					cells[cell + Vector3i.DOWN] = blocks.encode_block(18 if column == center else 16, rotation, 1)

static func attach(attachments: Array, key: String, position: Vector3, yaw: float = 0) -> void:
	attachments.append({"model":key, "transform":Transform3D(Basis(Vector3.UP, yaw), position)})
