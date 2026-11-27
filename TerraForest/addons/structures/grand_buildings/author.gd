# SPDX-License-Identifier: 0BSD
extends RefCounted
## Original offline plans. Every wall, stair, roof and buttress is an editable cell.
const Parts = preload("res://reviews/city_buildings/recipes.gd")
const Roof = preload("res://reviews/building_expansion/recipes.gd")
const Decorator = preload("res://addons/structures/mansion/author.gd")
const Catalog = preload("res://addons/structures/grand_buildings/catalog.gd")
const Packs = preload("res://addons/structures/pack_registry.gd")
var a: RefCounted
var decor: RefCounted
var blocks: Node3D
var flats: Array[Dictionary] = []
var floors: Array[Dictionary] = []
var entrances := PackedVector3Array()
var surface := 1

func prop(item: int, point: Vector3, yaw: float = 0) -> void:
	decor.prop(item, point, yaw)

func wall_x(x: int, z: int, length: int, y: int, doorway: int = -1) -> void:
	a.box(Vector3i(x,y,z), Vector3i(1,3,length))
	if doorway >= 0: a.door(Vector3i(x,y,doorway),true,2)

func wall_z(z: int, x: int, length: int, y: int, doorway: int = -1) -> void:
	a.box(Vector3i(x,y,z), Vector3i(length,3,1))
	if doorway >= 0: a.door(Vector3i(doorway,y,z),false,2)

func floor_area(rect: Rect2i, y: int, title: String) -> void:
	floors.append({"rect":rect,"level":y,"title":title})

func shell(rect: Rect2i, low: int, high: int, material: int = 0) -> void:
	a.box(Vector3i(rect.position.x,low,rect.position.y),Vector3i(rect.size.x,high-low,1),material)
	a.box(Vector3i(rect.position.x,low,rect.end.y-1),Vector3i(rect.size.x,high-low,1),material)
	a.box(Vector3i(rect.position.x,low,rect.position.y),Vector3i(1,high-low,rect.size.y),material)
	a.box(Vector3i(rect.end.x-1,low,rect.position.y),Vector3i(1,high-low,rect.size.y),material)

func stair_core(x: int, z: int, low: int, flights: int) -> void:
	# Identical 4 m flights have a continuous return aisle and two clear landings.
	for flight in flights: a.stair(x,z,low+flight*4)
	for y in range(low+4,low+flights*4+1,4):
		a.sign_room("STAIR LANDING",Vector3(x+3.5,y+1,z+5))

func apartment(x: int, back: int, y: int, south: bool, number: int, width: int = 10, depth: int = 20) -> void:
	# Each flat has an entrance/living room, bedroom and separate bathroom.
	var front := back+depth
	var entry := back if south else front
	a.door(Vector3i(x+6,y,entry),false,2)
	wall_z(back+9,x+1,width-1,y,x+1)
	a.door(Vector3i(x+6,y,back+9),false,2)
	wall_x(x+5,back+1,8,y)
	var bed_z := back+5 if south else back+4
	prop(720,Vector3(x+2.7,y,bed_z),PI)
	prop(721,Vector3(x+1.4,y,bed_z-1))
	prop(722,Vector3(x+2.7,y,back+7.7))
	prop(741,Vector3(x+7.5,y,back+2.2))
	prop(725,Vector3(x+7.5,y,back+5.0))
	prop(723,Vector3(x+2.5,y,back+11.2),PI)
	prop(726,Vector3(x+4.5,y,back+11.2),PI)
	prop(727,Vector3(x+2.8,y,back+16.7))
	prop(781,Vector3(x+3,y,back+14.6))
	prop(810,Vector3(x+7.3,y,back+13.7))
	prop(811,Vector3(x+7.3,y,back+15),0)
	a.sign_room("FLAT %03d / LIVING, BEDROOM & BATH"%number,Vector3(x+5,y+2,back+13))
	flats.append({"number":number,"level":y,"entrance":Vector3(x+7,y,entry+.5),"bed":Vector3(x+2.7,y,bed_z)})

func pilasters(rect: Rect2i, height: int, spacing: int) -> void:
	for x in range(rect.position.x,rect.end.x,spacing):
		for z in [rect.position.y-1,rect.end.y]: a.box(Vector3i(x,1,z),Vector3i(1,height-1,1),2)
	for z in range(rect.position.y+spacing,rect.end.y-1,spacing):
		for x in [rect.position.x-1,rect.end.x]: a.box(Vector3i(x,1,z),Vector3i(1,height-1,1),2)

func arrival(x: int, z: int, width: int = 6) -> void:
	a.slab(Rect2i(x,z,width,5),1,2,true)
	for column in range(x,x+width): a.cell(Vector3i(column,0,z+5),3,2,2)
	entrances.append(Vector3(x+width*.5,1,z+4))

func lancet(origin: Vector3i, side: bool = false) -> void:
	# Four metres of glazing and two independently editable quarter-arch caps.
	a.window(origin,side); a.window(origin+Vector3i(0,2,0),side)
	var top := origin+Vector3i(0,4,0)
	a.cell(top,11,2,3 if side else 2)
	a.cell(top+Vector3i(0,0,1) if side else top+Vector3i.RIGHT,11,2,1 if side else 0)

func court() -> void:
	var rect := Rect2i(0,0,69,45)
	a.shell(rect,5); a.windows(rect,5)
	for storey in 5:
		var y := 1+storey*4
		floor_area(Rect2i(1,1,67,43),y,"RESIDENTIAL LEVEL %d"%(storey+1))
		wall_z(20,1,60,y); wall_z(24,1,60,y)
		for boundary in range(10,61,10):
			wall_x(boundary,1,19,y); wall_x(boundary,25,19,y)
		wall_x(61,1,43,y,21)
		for column in 6:
			apartment(column*10,0,y,false,1+storey*12+column*2)
			apartment(column*10,24,y,true,2+storey*12+column*2)
		# The shared corridor meets a secondary exterior fire stair at the west end.
		a.door(Vector3i(0,y,21),true,2)
		a.slab(Rect2i(-7,15,7,15),y,2,storey==0,true)
		for z in [15,29]: a.box(Vector3i(-7,y,z),Vector3i(7,1,1),2,9,12 if z==15 else 4)
		floor_area(Rect2i(-7,15,7,15),y,"WEST FIRE LANDING")
	stair_core(64,17,1,5); stair_core(-5,18,1,5)
	a.flat_roof(rect,21,2)
	a.slab(Rect2i(-7,15,7,15),21,2,false,true)
	a.stair(-5,18,17); a.door(Vector3i(0,21,21),true,2)
	# Reopen the final roof aperture after roofing and enclose its landing.
	a.stair(64,17,17)
	shell(Rect2i(61,13,8,17),21,25,2)
	a.flat_roof(Rect2i(61,13,8,17),25,2); a.door(Vector3i(61,21,25),true,2)
	# Two low rooftop service pavilions and a cornice break the long roofline.
	for x in [8,43]:
		var room := Rect2i(x,7,15,11)
		shell(room,21,24,2); a.flat_roof(room,25,2)
		a.door(Vector3i(x+6,21,17),false,2)
	pilasters(rect,20,10)
	for x in [5,25,45]:
		a.door(Vector3i(x,1,44),false,2); arrival(x-2,45,6)
	a.door(Vector3i(68,1,21),true,2)
	# Open the entrance into each front flat rather than leaving a sealed vestibule.
	a.sign_room("FOUNDRY COURT / SIXTY SELF-CONTAINED FLATS",Vector3(34,3,23))

func tower() -> void:
	for storey in 10:
		var y := 1+storey*4
		var rect := Rect2i(0,0,55,47) if storey<3 else Rect2i(8,2,47,43)
		a.slab(rect,y,2,storey==0,true); shell(rect,y,y+4)
		for x in range(rect.position.x+2,rect.end.x-3,4):
			a.window(Vector3i(x,y+1,rect.position.y)); a.window(Vector3i(x,y+1,rect.end.y-1))
		for z in range(rect.position.y+3,rect.end.y-3,6):
			a.window(Vector3i(rect.position.x,y+1,z),true); a.window(Vector3i(54,y+1,z),true)
		floor_area(Rect2i(rect.position.x+1,rect.position.y+1,rect.size.x-2,rect.size.y-2),y,"TOWER LEVEL %d"%(storey+1))
		var first := 0 if storey<3 else 8
		var count := 4 if storey<3 else 3
		wall_z(20,first+1,47-first,y); wall_z(26,first+1,47-first,y)
		wall_x(48,rect.position.y+1,rect.size.y-2,y,22)
		for column in count:
			var x := first+column*12
			if column>0:
				wall_x(x,rect.position.y+1,19-rect.position.y,y)
				wall_x(x,27,rect.end.y-28,y)
			if storey==0:
				# Street-level shops have their own doors, counters, seating and storage.
				for z in [0,46]: a.door(Vector3i(x+5,y,z),false,2)
				for z in [5,32]:
					a.door(Vector3i(x+7,y,20 if z==5 else 26),false,2)
					prop(750,Vector3(x+3,y,z+3),PI); prop(755,Vector3(x+8,y,z+2))
					prop(810,Vector3(x+7,y,z+8)); prop(811,Vector3(x+7,y,z+9.3))
					a.sign_room("STREET SHOP / WORKROOM",Vector3(x+6,y+2,z+6))
			else:
				apartment(x,2 if storey>=3 else 0,y,false,flats.size()+1,12,18 if storey>=3 else 20)
				apartment(x,26,y,true,flats.size()+1,12)
		if storey in [2,5,8]:
			# Continuous street balconies have independent slab and guardrail cells.
			var z := rect.end.y
			a.slab(Rect2i(first+1,z,46-first,3),y,2,false,true)
			a.box(Vector3i(first+1,y,z+2),Vector3i(46-first,1,1),2,9,4)
			for x in range(first+1,47,12): a.door(Vector3i(x+6,y,z-1),false,2)
	stair_core(50,18,1,10)
	a.flat_roof(Rect2i(8,2,47,43),41,2)
	a.stair(50,18,37)
	# The top stair terminates in a weather-enclosed roof access pavilion.
	var crown := Rect2i(48,14,7,15)
	shell(crown,41,45,2); a.flat_roof(crown,45,2); a.door(Vector3i(48,41,23),true,2)
	pilasters(Rect2i(0,0,55,47),12,12)
	for x in [12,24,36]: arrival(x,47,6)
	a.door(Vector3i(54,1,22),true,2)
	a.slab(Rect2i(55,19,5,9),1,2,true); entrances.append(Vector3(59,1,23))
	a.sign_room("NEEDLE STREET / SHOPS & UPPER FLATS",Vector3(50,3,26))

func cathedral() -> void:
	# Cross-shaped crypt and undercroft retain generous clear aisles.
	var nave := Rect2i(32,0,41,81)
	var crossing := Rect2i(0,28,105,25)
	var cross_rects := [nave,crossing]
	for rect: Rect2i in cross_rects:
		for y in [-7,-3,1]: a.slab(rect,y,2,y==-7)
		shell(rect,-7,0,2)
		floor_area(rect,-7,"LOWER CRYPT"); floor_area(rect,-3,"UNDERCROFT")
		floor_area(rect,1,"NAVE & TRANSEPT")
	# Shared intersections are open on every underground and main level.
	for y in range(-7,26):
		if y in [-4,0]: continue
		for x in [32,72]: a.erase(Vector3i(x,y,29),Vector3i(1,1,23))
		for z in [28,52]: a.erase(Vector3i(33,y,z),Vector3i(39,1,1))
	# Tall nave, transepts and clerestory: no intermediate slab over the worship hall.
	for rect: Rect2i in cross_rects: shell(rect,1,26,2)
	for x in [32,72]: a.erase(Vector3i(x,1,29),Vector3i(1,24,23))
	for z in [28,52]: a.erase(Vector3i(33,1,z),Vector3i(39,24,1))
	for x in range(36,71,6):
		for z in [0,80]:
			for y in [3,11,19]: lancet(Vector3i(x,y,z))
	for z in range(5,79,6):
		if z in range(27,54): continue
		for x in [32,72]:
			for y in [3,11,19]: lancet(Vector3i(x,y,z),true)
	for x in range(4,103,6):
		if x in range(30,75): continue
		for z in [28,52]:
			for y in [3,11,19]: lancet(Vector3i(x,y,z))
	# Open galleries run inside both walls and join around the sanctuary and porch.
	for y in [9,17]:
		for rect: Rect2i in [Rect2i(33,1,6,79),Rect2i(66,1,6,79),Rect2i(39,1,27,6),Rect2i(39,74,27,6)]:
			a.slab(rect,y,2,false,true); floor_area(rect,y,"NAVE GALLERY")
		for x in [38,66]: a.box(Vector3i(x,y,7),Vector3i(1,1,67),2,9,16 if x==38 else 20)
		for z in [6,74]: a.box(Vector3i(39,y,z),Vector3i(27,1,1),2,9,4 if z==6 else 12)
	for x in [38,66]:
		for z in range(8,74,8): a.box(Vector3i(x,1,z),Vector3i(1,16,1),2,7)
	# Below-grade stair is inside a vaulted side chapel joined to the main crypt.
	var crypt_stair := Rect2i(22,55,11,26)
	for y in [-7,-3,1]: a.slab(crypt_stair,y,2,y==-7)
	shell(crypt_stair,-7,5,2); a.flat_roof(crypt_stair,5,2)
	stair_core(25,58,-7,2)
	for y in [-7,-3,1]: a.door(Vector3i(32,y,60),true,2)
	# Two bell towers include all landings, and the west connects the deep crypt.
	for x in [20,74]:
		var rect := Rect2i(x,63,11,18)
		a.shell(rect,13,2)
		# Narrow tower lights and large open belfry arches replace apartment fenestration.
		for y in range(3,43,8):
			for z in [63,80]: lancet(Vector3i(x+4,y,z))
			for side_x in [x,x+10]: lancet(Vector3i(side_x,y,65),true)
		for z in [63,80]:
			for column in [x+2,x+6]: lancet(Vector3i(column,45,z))
		for side_x in [x,x+10]:
			for z in [65,73]: lancet(Vector3i(side_x,45,z),true)
		for y in range(1,50,4): floor_area(Rect2i(x+1,64,9,16),y,"BELL TOWER LANDING")
		stair_core(x+3,68,1,12)
		for y in [1,9,17]:
			a.door(Vector3i(30 if x==20 else 74,y,76),true,2)
			a.slab(Rect2i(30 if x==20 else 72,75,3,4),y,2,false,true)
			a.door(Vector3i(32 if x==20 else 72,y,76),true,2)
		a.flat_roof(rect,53,2)
		Roof.shallow_roof(a,x+5,5,62,81,54)
		decor.close_gable(x+5,5,63,54); decor.close_gable(x+5,5,80,54)
	# Broad entry and side doors stay at the ordinary two-metre personnel height.
	a.door(Vector3i(50,1,80),false,4); arrival(48,81,10)
	a.canopy(Rect2i(47,81,11,4),7,2)
	for x in [0,104]: a.door(Vector3i(x,1,39),true,4)
	Roof.shallow_roof(a,52,19,-1,80,26)
	decor.close_gable(52,19,0,26); decor.close_gable(52,19,80,26)
	a.box(Vector3i(52,26,81),Vector3i(1,6,1),2)
	a.box(Vector3i(50,29,81),Vector3i(5,1,1),2)
	# Transept wings stop at the nave; each has a clean independent thin roof.
	for center in [15,89]:
		Roof.shallow_roof(a,center,15,27,52,26)
		decor.close_gable(center,15,28,26); decor.close_gable(center,15,52,26)
	# Rhythmic buttresses read at street height and as a large silhouette.
	for z in range(4,64,8):
		if z in range(26,55): continue
		for x in [28,73]:
			a.box(Vector3i(x,1,z),Vector3i(4,8,2),2)
			a.box(Vector3i(x+2 if x==28 else x,9,z),Vector3i(2,11,2),2)
	for x in [0,104]:
		for z in [28,52]: a.box(Vector3i(x,1,z),Vector3i(1,25,1),2)
	# Pews leave a ten-metre central procession aisle and side circulation.
	for z in range(14,70,5):
		for x in [43,60]:
			for offset in [0,2,4]: prop(811,Vector3(x+offset,1,z),PI)
	prop(810,Vector3(52,1,8)); prop(783,Vector3(59,1,5),PI)
	for y in [-7,-3]:
		for wall in [43,61]:
			for segment: Vector2i in [Vector2i(1,27),Vector2i(53,27)]:
				wall_x(wall,segment.x,segment.y,y)
			for z in [7,19,59,71]: a.door(Vector3i(wall,y,z),true,2)
		for z in [13,65]:
			wall_z(z,33,10,y); wall_z(z,62,10,y)
		for x in [35,64]:
			for z in [8,20,59,72]: prop(782,Vector3(x,y,z),PI/2)
		for x in [7,19,85,97]: prop(750,Vector3(x,y,40),PI)
		for x in [37,67]:
			for z in [5,17,56,68]:
				a.box(Vector3i(x,y,z),Vector3i(2,1,3),2,2)
				a.sign_room("CRYPT CHAMBER" if y==-7 else "ARCHIVE CHAMBER",Vector3(x,y+2,z))
	for y in [9,17]:
		for z in [16,32,48,64]: prop(782,Vector3(34.5,y,z),PI/2)
	a.sign_room("GREAT NAVE / 25 m CLEAR HEIGHT",Vector3(52,5,55))
	a.sign_room("LOWER CRYPT / ARCHIVES & BURIAL CHAMBERS",Vector3(52,-5,40))
	a.sign_room("UNDERCROFT / CHAPTER STORES",Vector3(52,-1,40))
	surface=9

func build(native_blocks: Node3D, index: int) -> Resource:
	if index<0 or index>=Catalog.IDS.size() or not Packs.discover(): return null
	blocks=native_blocks; a=Parts.Builder.new(blocks); decor=Decorator.new(); decor.a=a
	flats.clear(); floors.clear(); entrances.clear(); surface=1
	match index:
		0: court()
		1: cathedral()
		2: tower()
	var shift := Vector3i(0,surface-1,0)
	var records := PackedInt32Array()
	var positions: Array = a.cells.keys()
	positions.sort_custom(func(p: Vector3i,q: Vector3i): return p.x<q.x if p.x!=q.x else (p.z<q.z if p.z!=q.z else p.y<q.y))
	for p: Vector3i in positions:
		var d: Dictionary=blocks.decode_block(a.cells[p])
		var appearance := 2 if index==1 else 1
		if d.material==1: appearance=4 if d.shape in [19,20,21,22,23,32,33,34] else 3
		elif d.material==2: appearance=2
		if d.shape==8 and p.y>=0: appearance=2 if index==1 else 3
		var point := p+shift
		records.append_array(PackedInt32Array([point.x,point.y,point.z,blocks.encode_block(d.shape,d.rotation,d.material,appearance)]))
	for row: Dictionary in a.attachments: row.transform.origin+=Vector3(shift)
	for row: Dictionary in a.routes: row.start+=Vector3(shift); row.end+=Vector3(shift)
	for row: Dictionary in a.doors: row.center+=Vector3(shift)
	for row: Dictionary in a.rooms: row.position+=Vector3(shift)
	for row: Dictionary in decor.furniture: row.position+=Vector3(shift)
	for row: Dictionary in floors: row.level+=shift.y
	for row: Dictionary in flats: row.level+=shift.y; row.entrance+=Vector3(shift); row.bed+=Vector3(shift)
	for i in entrances.size(): entrances[i]+=Vector3(shift)
	var asset: Resource=ClassDB.instantiate("NativeBlockPrefab")
	if not asset.configure(records) or not asset.configure_model_attachments(a.attachments): return null
	var envelope: AABB=asset.get_bounds()
	for attachment: Dictionary in a.attachments:
		if not Packs.objects.has(attachment.model): continue
		var row: Dictionary=Packs.objects[attachment.model]
		var mesh: Mesh=load(row.directory+"/models/"+row.id+".tres")
		envelope=envelope.merge(attachment.transform*mesh.get_aabb())
		for box: AABB in mesh.get_meta("collision_boxes"): envelope=envelope.merge(attachment.transform*box)
	if not asset.configure_attachment_envelope(envelope.grow(.01)): return null
	asset.resource_name=Catalog.TITLES[index]
	asset.set_meta("grand_building_id",Catalog.IDS[index]); asset.set_meta("review_only",true)
	asset.set_meta("review_revision",1); asset.set_meta("asset_license","CC0-1.0")
	asset.set_meta("description",["Five storeys / 60 complete flats / twin stairs / shared corridors", "Cruciform cathedral / two crypt levels / two galleries / twin accessible bell towers", "Ten storeys / street shops / 58 flats / setbacks and balconies"][index])
	asset.set_meta("site_surface_offset",surface); asset.set_meta("finished_grade",1.0)
	asset.set_meta("stair_routes",a.routes); asset.set_meta("door_routes",a.doors); asset.set_meta("room_labels",a.rooms)
	asset.set_meta("floor_areas",floors); asset.set_meta("flats",flats); asset.set_meta("furnishing_layout",decor.furniture)
	asset.set_meta("entrances",entrances); asset.set_meta("lot_clearance",asset.get_bounds().grow(2))
	if index==1:
		asset.set_meta("basement_excavation",AABB(Vector3(0,0,0),Vector3(105,9,81)))
		asset.set_meta("basement_interior_m2",(39*79+2*31*23)*2)
	return asset
