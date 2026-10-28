extends RefCounted

const IDS := ["storage_s1", "police_p1", "medical_h1", "research_r1", "factory_f1", "apartments_a3"]
const TITLES := ["S1 / Storage warehouse", "P1 / Police station", "H1 / Medical centre", "R1 / Pharmaceutical research", "F1 / Factory", "A3 / Apartments"]
const ROLES := ["industrial", "civic", "medical", "research", "industrial", "residential"]
const FLOORS := [1, 2, 2, 3, 2, 4]
const DESCRIPTIONS := [
	"Twin-gable storage hall / receiving bays / shelving and store office",
	"Two-storey station / reception / interview rooms / vehicle garage",
	"L-shaped two-storey clinic / waiting hall / treatment rooms / ward",
	"Three-storey laboratory / bench rooms / archive / service annex",
	"Three production bays / two-storey office / loading hall / chimney",
	"Four storeys / sixteen compact units / shared stairs / balconies"
]

class Builder:
	extends RefCounted
	var blocks: Node
	var cells := {}
	var attachments: Array = []
	var openings: Array = []
	var routes: Array = []
	var doors: Array = []
	var rooms: Array = []
	var shells: Array = []
	var roof_spans: Array = []

	func _init(native_blocks: Node) -> void:
		blocks = native_blocks

	func cell(position: Vector3i, shape: int = 1, material: int = 0, rotation: int = 0) -> void:
		cells[position] = blocks.encode_block(shape, rotation, material)

	func box(origin: Vector3i, size: Vector3i, material: int = 0, shape: int = 1, rotation: int = 0) -> void:
		remove_windows(AABB(Vector3(origin), Vector3(size)))
		for column in range(origin.x, origin.x + size.x):
			for height in range(origin.y, origin.y + size.y):
				for row in range(origin.z, origin.z + size.z):
					cell(Vector3i(column, height, row), shape, material, rotation)

	func erase(origin: Vector3i, size: Vector3i) -> void:
		remove_windows(AABB(Vector3(origin), Vector3(size)))
		for column in range(origin.x, origin.x + size.x):
			for height in range(origin.y, origin.y + size.y):
				for row in range(origin.z, origin.z + size.z):
					cells.erase(Vector3i(column, height, row))

	func remove_windows(area: AABB) -> void:
		for index in range(openings.size() - 1, -1, -1):
			var opening: Dictionary = openings[index]
			if not area.intersects(opening.area): continue
			for position: Vector3i in opening.cells:
				cells[position] = opening.cells[position]
			attachments.erase(opening.attachment)
			openings.remove_at(index)

	func slab(rect: Rect2i, level: int, material: int = 2, ground: bool = false, closed_edges: bool = false) -> void:
		box(Vector3i(rect.position.x, level - 1, rect.position.y), Vector3i(rect.size.x, 1, rect.size.y), material, 1 if ground else 8)
		if closed_edges and not ground:
			for column in range(rect.position.x, rect.end.x):
				for row in [rect.position.y, rect.end.y - 1]: cell(Vector3i(column, level - 1, row), 1, material)
			for row in range(rect.position.y, rect.end.y):
				for column in [rect.position.x, rect.end.x - 1]: cell(Vector3i(column, level - 1, row), 1, material)

	func shell(rect: Rect2i, storeys: int, material: int = 0) -> void:
		shells.append({"rect": rect, "storeys": storeys})
		for floor_index in storeys:
			var level := 1 + floor_index * 4
			slab(rect, level, 2, floor_index == 0, true)
			box(Vector3i(rect.position.x, level, rect.position.y), Vector3i(rect.size.x, 4, 1), material)
			box(Vector3i(rect.position.x, level, rect.end.y - 1), Vector3i(rect.size.x, 4, 1), material)
			box(Vector3i(rect.position.x, level, rect.position.y), Vector3i(1, 4, rect.size.y), material)
			box(Vector3i(rect.end.x - 1, level, rect.position.y), Vector3i(1, 4, rect.size.y), material)

	func flat_roof(rect: Rect2i, level: int, material: int = 2) -> void:
		slab(rect, level, material, false, true)
		box(Vector3i(rect.position.x, level, rect.position.y), Vector3i(rect.size.x, 1, 1), material, 9, 12)
		box(Vector3i(rect.position.x, level, rect.end.y - 1), Vector3i(rect.size.x, 1, 1), material, 9, 4)
		box(Vector3i(rect.position.x, level, rect.position.y), Vector3i(1, 1, rect.size.y), material, 9, 16)
		box(Vector3i(rect.end.x - 1, level, rect.position.y), Vector3i(1, 1, rect.size.y), material, 9, 20)
		for column in [rect.position.x, rect.end.x - 1]:
			for row in [rect.position.y, rect.end.y - 1]: cell(Vector3i(column, level, row), 1, material)

	func attach(key: String, position: Vector3, yaw: float = 0) -> void:
		attachments.append({"model": key, "transform": Transform3D(Basis(Vector3.UP, yaw), position)})

	func door(origin: Vector3i, side: bool = false, width: int = 1) -> void:
		erase(origin, Vector3i(1 if side else width, 3, width if side else 1))
		for offset in width:
			var location := Vector3(origin) + Vector3(.5 if side else offset, 0, offset + 1 if side else .5)
			var yaw := PI / 2 if side else 0.0
			if offset % 2 == 1:
				location += Vector3(0, 0, -1) if side else Vector3.RIGHT
				yaw += PI
			attachments.append({"model": "architecture/wooden_door/v1", "transform": Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1, 1.25, 1)), location)})
		var middle := Vector3(origin) + Vector3(.5 if side else width * .5, 0, width * .5 if side else .5)
		doors.append({"center": middle, "side": side})

	func window(origin: Vector3i, side: bool = false) -> void:
		var size := Vector3i(1 if side else 2, 2, 2 if side else 1)
		var area := AABB(Vector3(origin), Vector3(size))
		remove_windows(area)
		var previous := {}
		for column in range(origin.x, origin.x + size.x):
			for height in range(origin.y, origin.y + size.y):
				for row in range(origin.z, origin.z + size.z):
					var position := Vector3i(column, height, row)
					if cells.has(position): previous[position] = cells[position]
		erase(origin, size)
		attach("architecture/wooden_window/v1", Vector3(origin) + Vector3(.5 if side else 1, 0, 1 if side else .5), PI / 2 if side else 0)
		openings.append({"area": area, "cells": previous, "attachment": attachments.back()})

	func windows(rect: Rect2i, floors: int, sides: bool = true) -> void:
		for floor_index in floors:
			var level := 2 + floor_index * 4
			for column in range(rect.position.x + 2, rect.end.x - 3, 4):
				window(Vector3i(column, level, rect.position.y))
				window(Vector3i(column, level, rect.end.y - 1))
			if sides:
				for row in range(rect.position.y + 2, rect.end.y - 3, 4):
					window(Vector3i(rect.position.x, level, row), true)
					window(Vector3i(rect.end.x - 1, level, row), true)

	func stair(column: int, row: int, base: int) -> void:
		erase(Vector3i(column, base + 3, row), Vector3i(2, 1, 4))
		for step in 4:
			for offset in 2:
				cell(Vector3i(column + offset, base + step, row + step), 3, 2)
			for side in [column - 1, column + 2]:
				var railing := Vector3i(side, base + 4, row + step)
				if not cells.has(railing): cell(railing, 9, 3, 20 if side < column else 16)
		routes.append({"kind": "stairs", "start": Vector3(column + .5, base + .02, row - .55), "end": Vector3(column + .5, base + 4.02, row + 4.8)})
		routes.append({"kind": "landing", "start": Vector3(column + 2.55, base + 4.02, row + 4.8), "end": Vector3(column + 2.55, base + 4.02, row - .55)})

	func canopy(rect: Rect2i, level: int = 4, material: int = 2) -> void:
		box(Vector3i(rect.position.x, level, rect.position.y), Vector3i(rect.size.x, 1, rect.size.y), material, 9)
		for column in [rect.position.x, rect.end.x - 1]:
			box(Vector3i(column, 1, rect.end.y - 1), Vector3i(1, level - 1, 1), material, 5)

	func desk(position: Vector3, yaw: float = 0) -> void:
		attach("furniture/table/v1", position, yaw)
		attach("furniture/chair/v1", position + Basis(Vector3.UP, yaw) * Vector3(0, 0, 1.45), yaw)

	func bed(origin: Vector3i) -> void:
		box(origin, Vector3i(2, 1, 3), 1, 2)
		box(origin + Vector3i(0, 0, -1), Vector3i(2, 1, 1), 2, 9, 12)

	func sign_room(title: String, position: Vector3) -> void:
		rooms.append({"title": title, "position": position})

	func finish(index: int) -> Resource:
		var records := PackedInt32Array()
		for position: Vector3i in cells:
			records.append_array(PackedInt32Array([position.x, position.y, position.z, cells[position]]))
		var prefab: Resource = ClassDB.instantiate("NativeBlockPrefab")
		if not prefab.configure(records) or not prefab.configure_model_attachments(attachments): return null
		prefab.resource_name = TITLES[index] + " / proposal R1"
		prefab.set_meta("review_only", true)
		prefab.set_meta("review_revision", 1)
		prefab.set_meta("city_role", ROLES[index])
		prefab.set_meta("description", DESCRIPTIONS[index])
		prefab.set_meta("finished_grade", 1.0)
		prefab.set_meta("stair_routes", routes)
		prefab.set_meta("door_routes", doors)
		prefab.set_meta("room_labels", rooms)
		prefab.set_meta("shells", shells)
		prefab.set_meta("roof_spans", roof_spans)
		prefab.set_meta("lot_clearance", prefab.get_bounds().grow(3))
		return prefab

static func build(blocks: Node, index: int) -> Resource:
	if index < 0 or index >= IDS.size(): return null
	var author := Builder.new(blocks)
	match index:
		0: storage(author)
		1: police(author)
		2: medical(author)
		3: research(author)
		4: factory(author)
		5: apartments(author)
	return author.finish(index)

static func gables(author: Builder, centers: Array, radius: int, back: int, front: int, peak: int) -> void:
	author.roof_spans.append({"left": int(centers.front()) - radius, "right": int(centers.back()) + radius + 1, "back": back, "front": front, "peak": peak})
	for center: int in centers:
		preload("res://reviews/modular_buildings/large_house_recipe.gd").roof(author.blocks, author.cells, center, radius, back, front, peak)

static func storage(author: Builder) -> void:
	var rect := Rect2i(0, 0, 18, 27)
	author.shell(rect, 1)
	author.box(Vector3i(0, 5, 0), Vector3i(18, 2, 1))
	author.box(Vector3i(0, 5, 26), Vector3i(18, 2, 1))
	for column in [0, 17]: author.box(Vector3i(column, 5, 0), Vector3i(1, 2, 27))
	gables(author, [4, 13], 4, 0, 26, 11)
	for column in [2, 11]: author.erase(Vector3i(column, 1, 26), Vector3i(5, 4, 1))
	for row in [3, 9, 15, 21]:
		author.window(Vector3i(0, 4, row), true)
		author.window(Vector3i(17, 4, row), true)
	for row in [3, 7, 11, 15]:
		for column in [3, 7, 11]:
			author.attach("furniture/shelf/v1", Vector3(column, 1, row))
			author.attach("storage/wooden_chest/v1", Vector3(column, 1, row + 1.4))
	author.box(Vector3i(1, 1, 19), Vector3i(6, 3, 1), 2)
	author.box(Vector3i(6, 1, 19), Vector3i(1, 3, 6), 2)
	author.door(Vector3i(6, 1, 22), true)
	author.desk(Vector3(3, 1, 22))
	author.sign_room("RECEIVING", Vector3(11, 3, 23))
	author.sign_room("STORAGE / DISPATCH", Vector3(8, 5.8, 12))
	author.routes.append({"kind": "bay", "start": Vector3(12.5, 1.02, 29), "end": Vector3(12.5, 1.02, 20)})

static func police(author: Builder) -> void:
	var main := Rect2i(0, 0, 19, 19)
	author.shell(main, 2)
	author.flat_roof(main, 9)
	author.windows(main, 2)
	author.shell(Rect2i(18, 5, 9, 14), 1, 2)
	author.flat_roof(Rect2i(18, 5, 9, 14), 5, 3)
	author.erase(Vector3i(20, 1, 18), Vector3i(5, 3, 1))
	author.door(Vector3i(9, 1, 18), false, 2)
	author.canopy(Rect2i(7, 19, 6, 3), 4)
	author.door(Vector3i(18, 1, 13), true)
	for level in [1, 5]:
		author.box(Vector3i(1, level, 9), Vector3i(17, 3, 1), 2)
		author.door(Vector3i(9, level, 9), false, 2)
		author.box(Vector3i(7, level, 1), Vector3i(1, 3, 8), 2)
		author.door(Vector3i(7, level, 6), true)
		author.desk(Vector3(4, level, 12))
		author.desk(Vector3(14, level, 12))
		author.attach("furniture/shelf/v1", Vector3(15, level, 3))
	author.stair(10, 2, 1)
	author.box(Vector3i(1, 1, 5), Vector3i(6, 3, 1), 2)
	author.door(Vector3i(4, 1, 5))
	author.bed(Vector3i(2, 1, 1))
	author.attach("storage/wooden_chest/v1", Vector3(15, 1, 6))
	author.sign_room("RECEPTION", Vector3(9.5, 3.6, 16))
	author.sign_room("INTERVIEW / HOLDING", Vector3(4, 3.5, 7))
	author.sign_room("OFFICES", Vector3(9, 7.5, 14))
	author.routes.append({"kind": "bay", "start": Vector3(22.5, 1.02, 22), "end": Vector3(22.5, 1.02, 10)})

static func medical(author: Builder) -> void:
	author.shell(Rect2i(0, 10, 25, 15), 2, 2)
	author.shell(Rect2i(0, 0, 11, 11), 2, 2)
	author.flat_roof(Rect2i(0, 10, 25, 15), 9)
	author.flat_roof(Rect2i(0, 0, 11, 11), 9)
	author.windows(Rect2i(0, 10, 25, 15), 2)
	for level in [1, 5]:
		author.erase(Vector3i(4, level, 10), Vector3i(3, 3, 1))
		for column in [2, 6]: author.window(Vector3i(column, level + 1, 0))
		for row in [2, 6]: author.window(Vector3i(0, level + 1, row), true)
		for column in [8, 16]: author.box(Vector3i(column, level, 11), Vector3i(1, 3, 5), 2)
		author.box(Vector3i(1, level, 16), Vector3i(23, 3, 1), 2)
		for column in [4, 11, 20]: author.door(Vector3i(column, level, 16))
		for column in [8, 16]: author.box(Vector3i(column, level, 20), Vector3i(1, 3, 4), 2)
		for column in [2, 19]:
			author.bed(Vector3i(column, level, 12))
			author.bed(Vector3i(column + 2, level, 21))
		author.desk(Vector3(12, level, 13))
		author.attach("storage/wooden_chest/v1", Vector3(22, level, 13))
	author.stair(3, 3, 1)
	author.door(Vector3i(11, 1, 24), false, 2)
	author.canopy(Rect2i(8, 25, 9, 4), 4)
	author.desk(Vector3(14, 1, 21))
	for column in [10, 12]: author.attach("furniture/chair/v1", Vector3(column, 1, 22.5))
	author.sign_room("MEDICAL CENTRE", Vector3(12, 3.7, 24.7))
	author.sign_room("TREATMENT / CONSULTATION", Vector3(13, 3.6, 18))
	author.sign_room("WARD", Vector3(5, 7.5, 22))
	for level in [1, 5]: author.routes.append({"kind": "wing connection", "start": Vector3(5.5, level + .02, 9), "end": Vector3(5.5, level + .02, 12)})

static func research(author: Builder) -> void:
	var main := Rect2i(0, 0, 19, 23)
	author.shell(main, 3, 2)
	author.flat_roof(main, 13, 3)
	author.windows(main, 3)
	for column in [0, 8, 17]: author.box(Vector3i(column, 1, 22), Vector3i(1, 12, 1), 3)
	for level in [1, 5, 9]:
		author.box(Vector3i(8, level, 1), Vector3i(1, 3, 20), 2)
		for row in [6, 16]: author.door(Vector3i(8, level, row), true)
		author.box(Vector3i(1, level, 11), Vector3i(7, 3, 1), 2)
		for row in [4, 14]:
			for column in [3, 6]: author.attach("furniture/table/v1", Vector3(column, level, row))
			author.attach("furniture/shelf/v1", Vector3(3, level, row + 3))
		author.attach("storage/wooden_chest/v1", Vector3(15, level, 6))
		author.desk(Vector3(14, level, 15))
	for base in [1, 5]: author.stair(11, 3, base)
	author.door(Vector3i(11, 1, 22), false, 2)
	author.canopy(Rect2i(10, 23, 6, 3), 4, 3)
	author.shell(Rect2i(18, 2, 5, 10), 1, 0)
	author.flat_roof(Rect2i(18, 2, 5, 10), 5)
	author.door(Vector3i(18, 1, 8), true)
	author.sign_room("PHARMACEUTICAL RESEARCH", Vector3(9, 11.8, 22.7))
	author.sign_room("LABORATORIES", Vector3(5, 7.6, 16))
	author.sign_room("RECORDS / SAMPLE ARCHIVE", Vector3(13, 11.6, 17))

static func factory(author: Builder) -> void:
	author.shell(Rect2i(0, 0, 27, 25), 1)
	for column in [0, 26]: author.box(Vector3i(column, 5, 0), Vector3i(1, 2, 25))
	for row in [0, 24]: author.box(Vector3i(0, 5, row), Vector3i(27, 2, 1))
	gables(author, [4, 13, 22], 4, 0, 24, 11)
	for column in [2, 11, 20]: author.erase(Vector3i(column, 1, 24), Vector3i(5, 4, 1))
	for row in [2, 8, 14, 20]: author.window(Vector3i(0, 4, row), true)
	for row in [4, 10, 16]:
		for column in [4, 13, 22]:
			author.attach("furniture/table/v1", Vector3(column, 1, row))
			author.attach("storage/wooden_chest/v1", Vector3(column, 1, row + 2))
	for column in [8, 17]:
		for row in [6, 14]: author.box(Vector3i(column, 1, row), Vector3i(1, 6, 1), 3)
	author.shell(Rect2i(26, 12, 9, 17), 2, 2)
	author.flat_roof(Rect2i(26, 12, 9, 17), 9, 3)
	for level in [1, 5]:
		for row in [14, 20, 24]: author.window(Vector3i(34, level + 1, row), true)
		author.window(Vector3i(28, level + 1, 28))
		author.desk(Vector3(31, level, 24))
	author.door(Vector3i(31, 1, 28))
	author.door(Vector3i(26, 1, 20), true)
	author.stair(29, 14, 1)
	for level in range(1, 19):
		for column in range(29, 32):
			for row in range(3, 6):
				if column in [29, 31] or row in [3, 5]: author.cell(Vector3i(column, level, row), 1, 2 if level in [6, 12, 18] else 0)
	author.slab(Rect2i(28, 2, 5, 5), 1, 2, true)
	author.sign_room("PRODUCTION HALL", Vector3(12, 6.1, 22))
	author.sign_room("OFFICE / DISPATCH", Vector3(30, 7.5, 25))
	author.routes.append({"kind": "bay", "start": Vector3(12.5, 1.02, 27), "end": Vector3(12.5, 1.02, 19)})

static func apartments(author: Builder) -> void:
	var rect := Rect2i(0, 0, 23, 19)
	author.shell(rect, 4)
	author.flat_roof(rect, 17, 2)
	author.windows(rect, 4)
	for level in [1, 5, 9, 13]:
		for column in [9, 13]:
			author.box(Vector3i(column, level, 1), Vector3i(1, 3, 17), 2)
			for row in [7, 14]: author.door(Vector3i(column, level, row), true)
		for column in [1, 14]: author.box(Vector3i(column, level, 10), Vector3i(8, 3, 1), 2)
		for column in [3, 16]:
			for row in [3, 13]:
				author.bed(Vector3i(column, level, row))
				author.desk(Vector3(column + 3, level, row + 1))
				author.attach("furniture/shelf/v1", Vector3(column, level, row + 4))
		if level > 1:
			for column in [1, 14]:
				author.slab(Rect2i(column, 19, 8, 4), level)
				author.box(Vector3i(column, level, 22), Vector3i(8, 1, 1), 3, 9, 4)
				for side in [column, column + 7]: author.box(Vector3i(side, level, 19), Vector3i(1, 1, 3), 3, 9, 16 if side == column else 20)
				author.door(Vector3i(column + 3, level, 18))
	for base in [1, 5, 9]: author.stair(10, 2, base)
	author.door(Vector3i(11, 1, 18))
	author.canopy(Rect2i(10, 19, 3, 3), 4, 2)
	author.sign_room("APARTMENTS A3", Vector3(11.5, 3.6, 18.7))
	author.sign_room("SHARED STAIR / 4 FLOORS", Vector3(11.5, 7.5, 12))
