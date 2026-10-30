# SPDX-License-Identifier: 0BSD
extends RefCounted
## Offline authoring. Runtime loads the baked, individually addressable cells.
const Parts = preload("res://reviews/city_buildings/recipes.gd")
const IDS := ["trader_t1", "town_hall_t1", "church_c1", "school_s2", "warehouse_w1"]
const TITLES := ["Trader's house", "Town hall", "Church", "School", "Warehouse"]
const DESCRIPTIONS := [
	"Covered arrival / sales counter / private stockroom / one resident trader",
	"Civic portico / public hall / council chamber / records basement",
	"Tall nave / bell tower / vestry / stair-accessed crypt and stores",
	"Two-storey classrooms / library wing / shared corridor / supplies basement",
	"Three roof bays / two loading entrances / dispatch office / secure stores"
]
const FLOORS := [1, 2, 1, 2, 1]
const BASEMENTS := [Rect2i(), Rect2i(1, 1, 11, 13), Rect2i(1, 1, 11, 13), Rect2i(1, 1, 11, 11), Rect2i(1, 1, 11, 13)]
const INSIDE := [Vector3(6.5, 2.7, 13.8), Vector3(12, 2.7, 18), Vector3(6.5, 2.7, 25), Vector3(16, 2.7, 10.8), Vector3(14, 2.7, 25)]

static func build(blocks: Node, index: int) -> Resource:
	if index < 0 or index >= IDS.size(): return null
	var a := Parts.Builder.new(blocks)
	match index:
		0: trader(a)
		1: town_hall(a)
		2: church(a)
		3: school(a)
		4: warehouse(a)
	if index > 0: basement(a, BASEMENTS[index], 3, 3 if index == 3 else 4)
	var records := PackedInt32Array()
	for p: Vector3i in a.cells:
		records.append_array(PackedInt32Array([p.x, p.y, p.z, a.cells[p]]))
	var asset: Resource = ClassDB.instantiate("NativeBlockPrefab")
	if not asset.configure(records) or not asset.configure_model_attachments(a.attachments): return null
	asset.resource_name = TITLES[index] + " / R1 review"
	asset.set_meta("review_only", true)
	asset.set_meta("review_revision", 1)
	asset.set_meta("finished_grade", 1.0)
	asset.set_meta("stair_routes", a.routes)
	asset.set_meta("door_routes", a.doors)
	asset.set_meta("room_labels", a.rooms)
	asset.set_meta("roof_spans", a.roof_spans)
	asset.set_meta("description", DESCRIPTIONS[index])
	if index > 0:
		var r: Rect2i = BASEMENTS[index]
		asset.set_meta("basement_excavation", AABB(Vector3(r.position.x, -4, r.position.y), Vector3(r.size.x, 5, r.size.y)))
		asset.set_meta("basement_interior_m2", (r.size.x - 2) * (r.size.y - 2))
	else:
		asset.set_meta("trader_anchor", Transform3D(Basis.IDENTITY, Vector3(6, 1, 8.1)))
		asset.set_meta("trader_id", "civic_trader_01")
	return asset

static func basement(a: Parts.Builder, rect: Rect2i, stair_x: int, stair_z: int) -> void:
	a.slab(rect, -3, 2, true)
	for x in range(rect.position.x, rect.end.x):
		for z in [rect.position.y, rect.end.y - 1]: a.box(Vector3i(x, -3, z), Vector3i(1, 3, 1), 2)
	for z in range(rect.position.y, rect.end.y):
		for x in [rect.position.x, rect.end.x - 1]: a.box(Vector3i(x, -3, z), Vector3i(1, 3, 1), 2)
	a.stair(stair_x, stair_z, -3)
	# The basement is partial: supported ground slabs remain outside this envelope.
	a.attach("furniture/shelf/v1", Vector3(9, -3, 3))
	a.attach("storage/wooden_chest/v1", Vector3(9, -3, 5))
	a.attach("storage/wooden_chest/v1", Vector3(9, -3, 7))
	a.sign_room("BASEMENT / STORES", Vector3(7, -1, 9))

static func apron(a: Parts.Builder, rect: Rect2i) -> void:
	a.slab(rect, 1, 2, true)

static func trader(a: Parts.Builder) -> void:
	var rect := Rect2i(0, 0, 13, 17)
	a.shell(rect, 1)
	a.windows(rect, 1)
	a.door(Vector3i(6, 1, 16))
	a.box(Vector3i(1, 1, 6), Vector3i(11, 4, 1), 1)
	a.door(Vector3i(9, 1, 6))
	Parts.gables(a, [6], 6, 0, 16, 11)
	apron(a, Rect2i(3, 17, 7, 5))
	a.canopy(Rect2i(3, 17, 7, 3), 4, 1)
	for x in [4, 6, 8]: a.attach("furniture/table/v1", Vector3(x, 1, 10.2))
	for x in [3, 6, 9]:
		a.attach("furniture/shelf/v1", Vector3(x, 1, 2))
		a.attach("storage/wooden_chest/v1", Vector3(x, 1, 4.3))
	a.attach("furniture/shelf/v1", Vector3(2, 1, 8.2), PI / 2)
	a.sign_room("TRADER / SUPPLIES", Vector3(6.5, 3.6, 15.7))
	a.routes.append({"kind":"arrival", "start":Vector3(6.5, 1.02, 21), "end":Vector3(6.5, 1.02, 12)})

static func town_hall(a: Parts.Builder) -> void:
	var rect := Rect2i(0, 0, 25, 21)
	a.shell(rect, 2, 2)
	a.windows(rect, 2)
	a.flat_roof(rect, 9, 2)
	# Central raised chamber gives the hall a civic silhouette over low wings.
	a.box(Vector3i(8, 9, 0), Vector3i(1, 2, 21), 2)
	a.box(Vector3i(16, 9, 0), Vector3i(1, 2, 21), 2)
	Parts.gables(a, [12], 4, 0, 20, 14)
	for floor_y in [1, 5]:
		a.box(Vector3i(1, floor_y, 12), Vector3i(23, 3, 1), 2)
		a.door(Vector3i(11, floor_y, 12), false, 2)
		a.desk(Vector3(18, floor_y, 5))
		a.attach("furniture/shelf/v1", Vector3(21, floor_y, 2))
	a.stair(3, 4, 1)
	a.door(Vector3i(11, 1, 20), false, 2)
	apron(a, Rect2i(6, 21, 13, 6))
	a.canopy(Rect2i(7, 21, 11, 4), 5, 2)
	for x in [10, 14]: a.box(Vector3i(x, 1, 24), Vector3i(1, 4, 1), 2, 7)
	for x in [8, 12, 16]:
		a.desk(Vector3(x, 5, 16))
		a.attach("furniture/chair/v1", Vector3(x, 1, 16), PI)
	a.sign_room("PUBLIC HALL", Vector3(12, 3.5, 18))
	a.sign_room("COUNCIL CHAMBER", Vector3(12, 7.5, 18))
	a.routes.append({"kind":"arrival", "start":Vector3(11.5, 1.02, 26), "end":Vector3(11.5, 1.02, 14)})

static func church(a: Parts.Builder) -> void:
	var nave := Rect2i(0, 0, 13, 29)
	a.shell(nave, 2, 2)
	a.erase(Vector3i(1, 4, 1), Vector3i(11, 1, 27))
	for z in [3, 9, 15, 21]:
		for x in [0, 12]:
			a.window(Vector3i(x, 5, z), true)
			a.box(Vector3i(x - 1 if x == 0 else x + 1, 1, z - 1), Vector3i(1, 6, 1), 2)
	Parts.gables(a, [6], 6, 0, 28, 15)
	a.shell(Rect2i(12, 0, 9, 13), 1, 0)
	Parts.gables(a, [16], 4, 0, 12, 9)
	a.windows(Rect2i(12, 0, 9, 13), 1)
	# The low annex roof must meet, not overwrite, the tall nave's shared wall.
	a.box(Vector3i(12, 1, 0), Vector3i(1, 8, 14), 2)
	a.door(Vector3i(12, 1, 9), true)
	a.desk(Vector3(17, 1, 7))
	a.shell(Rect2i(3, 28, 7, 7), 3, 2)
	a.erase(Vector3i(4, 1, 28), Vector3i(5, 3, 1))
	a.door(Vector3i(6, 1, 34))
	for z in [28, 34]: a.window(Vector3i(5, 10, z))
	Parts.gables(a, [6], 3, 28, 34, 16)
	# Each piece of the cross remains a normal one-metre native cell.
	a.cell(Vector3i(6, 16, 31), 1, 1)
	a.box(Vector3i(6, 17, 31), Vector3i(1, 3, 1), 1, 9, 12)
	a.box(Vector3i(5, 18, 31), Vector3i(3, 1, 1), 1, 9, 12)
	for z in [13, 17, 21, 25]:
		for x in [2, 8]:
			a.box(Vector3i(x, 1, z), Vector3i(3, 1, 1), 1, 2)
			a.box(Vector3i(x, 1, z + 1), Vector3i(3, 1, 1), 1, 9, 4)
	a.attach("furniture/table/v1", Vector3(7, 1, 10))
	apron(a, Rect2i(3, 35, 7, 5))
	a.sign_room("NAVE", Vector3(6.5, 7.5, 20))
	a.routes.append({"kind":"arrival", "start":Vector3(6.5, 1.02, 39), "end":Vector3(6.5, 1.02, 15)})

static func school(a: Parts.Builder) -> void:
	var main := Rect2i(0, 0, 29, 13)
	a.shell(main, 2)
	a.windows(main, 2)
	a.flat_roof(main, 9, 2)
	var wing := Rect2i(0, 12, 11, 13)
	a.shell(wing, 1)
	a.windows(wing, 1)
	Parts.gables(a, [5], 5, 12, 24, 10)
	a.box(Vector3i(0, 5, 12), Vector3i(11, 4, 1))
	a.erase(Vector3i(5, 1, 12), Vector3i(3, 3, 1))
	a.stair(3, 3, 1)
	for y in [1, 5]:
		a.box(Vector3i(10, y, 1), Vector3i(1, 3, 7), 2)
		a.box(Vector3i(20, y, 1), Vector3i(1, 3, 7), 2)
		a.box(Vector3i(10, y, 8), Vector3i(18, 3, 1), 2)
		for x in [14, 24]:
			a.door(Vector3i(x, y, 8))
			for z in [3, 5.8]: a.desk(Vector3(x, y, z))
			a.attach("furniture/shelf/v1", Vector3(x + 3, y, 2))
	a.door(Vector3i(15, 1, 12), false, 2)
	apron(a, Rect2i(12, 13, 9, 5))
	a.canopy(Rect2i(13, 13, 7, 3), 4, 2)
	for z in [16, 20]:
		a.attach("furniture/shelf/v1", Vector3(2, 1, z), PI / 2)
		a.desk(Vector3(7, 1, z))
	a.sign_room("LIBRARY", Vector3(5, 3.5, 23))
	a.routes.append({"kind":"arrival", "start":Vector3(15.5, 1.02, 17), "end":Vector3(15.5, 1.02, 10)})

static func warehouse(a: Parts.Builder) -> void:
	var rect := Rect2i(0, 0, 27, 29)
	a.shell(rect, 1)
	for x in [0, 26]: a.box(Vector3i(x, 5, 0), Vector3i(1, 2, 29))
	for z in [0, 28]: a.box(Vector3i(0, 5, z), Vector3i(27, 2, 1))
	Parts.gables(a, [4, 13, 22], 4, 0, 28, 11)
	for x in [11, 20]: a.erase(Vector3i(x, 1, 28), Vector3i(5, 4, 1))
	for z in [3, 9, 15, 21]:
		a.window(Vector3i(0, 4, z), true)
		a.window(Vector3i(26, 4, z), true)
	for z in [13, 17, 21]:
		for x in [3, 7, 18, 23]:
			a.attach("furniture/shelf/v1", Vector3(x, 1, z))
			a.attach("storage/wooden_chest/v1", Vector3(x, 1, z + 1.3))
	a.box(Vector3i(15, 1, 1), Vector3i(1, 3, 8), 2)
	a.box(Vector3i(15, 1, 9), Vector3i(11, 3, 1), 2)
	a.door(Vector3i(20, 1, 9))
	a.desk(Vector3(20, 1, 4))
	a.door(Vector3i(5, 1, 28))
	apron(a, Rect2i(2, 29, 25, 6))
	a.sign_room("DISPATCH / RECEIVING", Vector3(16, 5.4, 26))
	for x in [13.5, 22.5]: a.routes.append({"kind":"loading bay", "start":Vector3(x, 1.02, 34), "end":Vector3(x, 1.02, 25)})
