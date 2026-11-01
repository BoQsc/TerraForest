# SPDX-License-Identifier: 0BSD
extends RefCounted
const Civic=preload("res://reviews/civic_buildings/recipes.gd")
const Parts=preload("res://reviews/city_buildings/recipes.gd")
const SOURCES=["civic_review_trader_t1","civic_review_town_hall_t1","civic_review_church_c1","civic_review_school_s2","civic_review_warehouse_w1","cottage_thin_roof_a2","village_shop_thin_roof_b2","village_shop_hipped_r1","large_house_c1"]
const IDS=["trader_t1","town_hall_t1","church_c1","school_s2","warehouse_w1","cottage_a2","shop_b2","shop_b1","house_c1"]

static func build(blocks:Node,index:int)->Resource:
	var baseline:Resource=load("res://addons/structures/prefabs/"+SOURCES[index]+".tres")
	var result:Resource=baseline.duplicate()
	var cells:={}
	var attachments:Array=baseline.get_model_attachments()
	var records:PackedInt32Array=baseline.get_records()
	for offset in range(0,records.size(),4):cells[Vector3i(records[offset],records[offset+1],records[offset+2])]=records[offset+3]
	if index==3:
		var author:=Parts.Builder.new(blocks);school(author);Civic.basement(author,Civic.BASEMENTS[3],3,3)
		cells.clear()
		for cell:Vector3i in author.cells:cells[cell+Vector3i(0,4,0)]=author.cells[cell]
		# Attachments and circulation come from the exact same school recipe.
		var shifted:=[]
		for attachment:Dictionary in author.attachments:
			var copy:Dictionary=attachment.duplicate(true);copy.transform.origin+=Vector3(0,4,0);shifted.append(copy)
		attachments=shifted
	if index==1:
		hip_canopy(blocks,cells,Rect2i(7,21,11,4),9)
		crown(blocks,cells,Rect2i(0,0,25,21),12)
		# Top caps sit on the existing one-cell parapet, independent of it.
		for x in range(0,25):
			for z in range(0,21):
				if x not in [0,24] and z not in [0,20]:continue
				var point:=Vector3i(x,14,z);var corner:bool=x in [0,24] and z in [0,20]
				var rotation:int=(0 if x==0 else 1) if z==0 else (3 if x==0 else 2)
				if not corner:rotation=1 if z in [0,20] else 0
				if not cells.has(point):cells[point]=blocks.encode_block(31 if corner else 30,rotation,2)
	records.clear()
	for cell:Vector3i in cells:
		var word:int=cells[cell];var decoded:Dictionary=blocks.decode_block(word)
		if decoded.material==1 and decoded.shape in [4,12]:
			decoded.rotation=decoded.rotation if decoded.shape==12 else (decoded.rotation+1)%4
			decoded.shape=36 if decoded.shape==12 else 35
		var appearance:int=[0,3,1,5][decoded.material]
		if decoded.material==2 and (decoded.shape==8 or cell.y<=int(baseline.get_meta("site_surface_offset",1))):appearance=2
		if decoded.shape in [4,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27]:appearance=6 if index in [0,5] else (5 if index==4 else 4)
		if decoded.shape in [28,29,30,31]:appearance=7
		if decoded.shape>=32:appearance=6 if index in [0,5] else (5 if index==4 else 4)
		if index==2 and decoded.material==2:appearance=2
		if index==3 and decoded.material==0:appearance=1
		records.append_array(PackedInt32Array([cell.x,cell.y,cell.z,blocks.encode_block(decoded.shape,decoded.rotation,decoded.material,appearance)]))
	if not result.configure(records) or not result.configure_model_attachments(attachments):return null
	result.resource_name=baseline.resource_name+" / Expansion E2"
	result.set_meta("expansion_revision","E2");result.set_meta("expansion_id",IDS[index]);result.set_meta("review_only",true)
	result.set_meta("baseline_sha256",FileAccess.get_sha256("res://addons/structures/prefabs/"+SOURCES[index]+".tres"))
	for key:StringName in result.get_meta_list():
		if str(key).begins_with("approved_"):result.remove_meta(key)
	return result

static func hip_canopy(blocks:Node,cells:Dictionary,rect:Rect2i,y:int)->void:
	for x in rect.size.x:
		for z in rect.size.y:
			var dx:=mini(x,rect.size.x-1-x);var dz:=mini(z,rect.size.y-1-z)
			var phase:=mini(dx,dz)%2;var shape:=19+phase;var rotation:=0
			if dx==dz:
				shape=24+phase;rotation=0 if x<rect.size.x/2 and z<rect.size.y/2 else (1 if x>=rect.size.x/2 and z<rect.size.y/2 else (2 if x>=rect.size.x/2 else 3))
			elif dx<dz:rotation=0 if x<rect.size.x/2 else 2
			else:rotation=1 if z<rect.size.y/2 else 3
			cells[Vector3i(rect.position.x+x,y+mini(dx,dz)/2,rect.position.y+z)]=blocks.encode_block(shape,rotation,2)

static func crown(blocks:Node,cells:Dictionary,rect:Rect2i,y:int)->void:
	for z in range(rect.position.y,rect.end.y):
		for edge in [[rect.position.x-1,2],[rect.end.x,0]]:
			var point:=Vector3i(edge[0],y,z)
			if not cells.has(point):cells[point]=blocks.encode_block(28,edge[1],2)
	for x in range(rect.position.x,rect.end.x):
		for edge in [[rect.position.y-1,3],[rect.end.y,1]]:
			var point:=Vector3i(x,y,edge[0])
			if not cells.has(point):cells[point]=blocks.encode_block(28,edge[1],2)
	for corner in [[rect.position.x-1,rect.position.y-1,2],[rect.end.x,rect.position.y-1,3],[rect.end.x,rect.end.y,0],[rect.position.x-1,rect.end.y,1]]:
		var point:=Vector3i(corner[0],y,corner[1])
		if not cells.has(point):cells[point]=blocks.encode_block(29,corner[2],2)

static func shallow_roof(a:Parts.Builder,center:int,radius:int,back:int,front:int,eave:int)->void:
	# An even half-span meets the central low ridge at an integer height.
	assert((radius+1)%2==0)
	for x in range(center-radius-1,center+radius+2):
		var step:=radius+1-absi(x-center)
		var y:=eave+step/2
		var phase:=step%2
		var rotation:=0 if x<=center else 2
		for z in range(back,front+2):
			var p:=Vector3i(x,y,z)
			if (z==front and x>=center-radius and x<=center+radius) or x in [center-radius,center+radius]:
				for height in range(eave,y):a.cell(Vector3i(x,height,z),1,1)
				a.cell(p,34 if x==center else 32+phase,1,rotation)
			else:
				a.cell(p,22 if x==center else 19+phase,1,rotation)
				if phase==0 and not a.cells.has(p+Vector3i.DOWN):a.cell(p+Vector3i.DOWN,23 if x==center else 21,1,rotation)

static func school(a: Parts.Builder) -> void:
	var main := Rect2i(0, 0, 29, 13)
	a.shell(main, 2)
	a.windows(main, 2)
	a.flat_roof(main, 9, 2)
	var wing := Rect2i(0, 12, 11, 13)
	a.shell(wing, 1)
	a.windows(wing, 1)
	shallow_roof(a,5,5,13,24,5)
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
	Civic.apron(a, Rect2i(12, 13, 9, 5))
	a.canopy(Rect2i(13, 13, 7, 3), 4, 2)
	for z in [16, 20]:
		a.attach("furniture/shelf/v1", Vector3(2, 1, z), PI / 2)
		a.desk(Vector3(7, 1, z))
	a.sign_room("LIBRARY", Vector3(5, 3.5, 23))
	a.routes.append({"kind":"arrival", "start":Vector3(15.5, 1.02, 17), "end":Vector3(15.5, 1.02, 10)})

