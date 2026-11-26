# SPDX-License-Identifier: 0BSD
extends RefCounted
## Original courtyard manor; offline authoring, all fabric remains editable cells.
const Parts=preload("res://reviews/city_buildings/recipes.gd")
const Roof=preload("res://reviews/building_expansion/recipes.gd")
const Packs=preload("res://addons/structures/pack_registry.gd")
const PATH:="res://addons/structures/mansion/homestead_manor.tres"
var a: RefCounted
var used: Dictionary={}
var furniture: Array[Dictionary]=[]
var offsets: Dictionary={}

func floor_offset(item: int) -> float:
	if offsets.has(item): return offsets[item]
	var row: Dictionary=Packs.by_item[item]; var mesh: Mesh=load(row.directory+"/models/"+row.id+".tres")
	var low:=0.0
	for box: AABB in mesh.get_meta("collision_boxes"): low=minf(low,box.position.y)
	offsets[item]=-low
	return -low

func prop(item: int, point: Vector3, yaw: float=0) -> void:
	var row: Dictionary=Packs.by_item[item]
	point.y+=floor_offset(item)
	a.attach(row.key,point,yaw); used[item]=true
	furniture.append({"item":item,"position":point,"yaw":yaw})

func top(item: int, point: Vector3) -> Vector3:
	var row: Dictionary=Packs.by_item[item]
	var mesh: Mesh=load(row.directory+"/models/"+row.id+".tres")
	# Use the actual work surface, not a headboard, tap, splashback or handle.
	var surfaces: Dictionary={720:.6425,725:1.01,726:.913,801:.7925,813:.6775}
	return point+Vector3.UP*(float(surfaces.get(item,mesh.get_aabb().end.y))+floor_offset(item)+.008)

func wall_x(x: int, back: int, front: int, level: int, opening: int) -> void:
	a.box(Vector3i(x,level,back),Vector3i(1,3,front-back+1),0)
	a.door(Vector3i(x,level,opening),true,2)

func wall_z(z: int, left: int, right: int, level: int, opening: int) -> void:
	a.box(Vector3i(left,level,z),Vector3i(right-left+1,3,1),0)
	a.door(Vector3i(opening,level,z),false,2)

func close_gable(center: int, radius: int, z: int, eave: int) -> void:
	for x in range(center-radius,center+radius+1):
		var step:=radius+1-absi(x-center); var y:=eave+step/2
		for height in range(eave,y): a.cell(Vector3i(x,height,z),1,1)
		a.cell(Vector3i(x,y,z),34 if x==center else 32+step%2,1,0 if x<=center else 2)

func build(blocks: Node3D) -> Resource:
	if not Packs.discover(): return null
	a=Parts.Builder.new(blocks); used.clear(); furniture.clear()
	# U-shaped composition: a central reception hall and two quieter garden wings.
	var main:=Rect2i(0,0,39,13); var west:=Rect2i(0,12,11,19); var east:=Rect2i(28,12,11,19)
	for rect: Rect2i in [main,west,east]: a.shell(rect,2); a.windows(rect,2)
	for level in [1,5]:
		# Internal connections replace the shared end walls; rooms have two-cell doors.
		a.erase(Vector3i(1,level,12),Vector3i(9,3,1)); a.erase(Vector3i(29,level,12),Vector3i(9,3,1))
		wall_x(11,1,11,level,7); wall_x(27,1,11,level,7)
		wall_z(12,1,9,level,7); wall_z(12,29,37,level,29)
		wall_z(21,1,9,level,7); wall_z(21,29,37,level,29)
	# Deliberate arrival: two-storey recessed hall, a porch and a sheltered courtyard.
	a.door(Vector3i(18,1,12),false,2)
	a.door(Vector3i(7,1,30),false,2); a.door(Vector3i(29,1,30),false,2)
	a.door(Vector3i(10,1,17),true,2); a.door(Vector3i(28,1,17),true,2)
	# A 3-metre-wide stair and generous landing leave a straight entrance route.
	a.erase(Vector3i(16,4,3),Vector3i(3,1,4))
	for step in 4:
		for x in range(16,19): a.cell(Vector3i(x,1+step,3+step),3,1)
		for side in [15,19]: a.cell(Vector3i(side,5,3+step),9,1,20 if side==15 else 16)
	a.routes.append({"kind":"main stair","start":Vector3(17.5,1.02,2.2),"end":Vector3(17.5,5.02,7.8)})
	# Readable thin roofs: the long rear span turns across the paired garden gables.
	Roof.shallow_roof(a,5,5,-1,30,9); Roof.shallow_roof(a,33,5,-1,30,9)
	# Centre gable is wider/higher, giving the entrance a distinct silhouette.
	Roof.shallow_roof(a,19,7,-1,12,10)
	close_gable(5,5,0,9); close_gable(33,5,0,9); close_gable(19,7,0,10)
	for x in [11,27]:
		for z in range(0,13): a.cell(Vector3i(x,9,z),1,1)
	for x in range(11,28):
		for z in range(0,13):
			if not a.cells.has(Vector3i(x,8,z)): a.cell(Vector3i(x,8,z),8,1)
		for z in [0,12]:
			for y in [8,9]: a.cell(Vector3i(x,y,z),1,0)
	# Front portico stays below the central roof; pillars are individual grid blocks.
	a.slab(Rect2i(14,13,11,5),1,2,true)
	a.canopy(Rect2i(14,13,11,5),4,2)
	a.slab(Rect2i(14,13,11,5),5,1,false,true)
	a.door(Vector3i(18,5,12),false,2)
	for x in range(14,25): a.cell(Vector3i(x,5,17),9,1,4)
	for z in range(13,17):
		for x in [14,24]: a.cell(Vector3i(x,5,z),9,1,20 if x==14 else 16)
	for x in [14,24]:
		for y in range(1,4): a.cell(Vector3i(x,y,17),7,2)
	# Courtyard paths at floor height, with a broad grounded arrival step.
	for rect: Rect2i in [Rect2i(17,18,5,17),Rect2i(10,17,19,3),Rect2i(6,30,4,5),Rect2i(29,30,4,5)]: a.slab(rect,1,2,true)
	for x in range(17,22): a.cell(Vector3i(x,0,35),3,2,2)
	# Original limestone/plaster, timber floors and slate; no new texture inputs.
	for cell: Vector3i in a.cells:
		var decoded: Dictionary=blocks.decode_block(a.cells[cell]); var appearance:=1
		if decoded.shape in [19,20,21,22,23,32,33,34]: appearance=4
		elif decoded.material==1: appearance=3
		elif decoded.material==2: appearance=2
		var exterior: bool=cell.x in [0,38] or cell.z in [0,30] or (cell.x in [10,28] and cell.z>=12) or (cell.z==12 and cell.x>=11 and cell.x<=27)
		var indoors: bool=cell.x>0 and cell.x<38 and cell.z>0 and (cell.z<12 or cell.x<10 or cell.x>28) and cell.z<30
		if cell.y in [0,4] and indoors: appearance=3; decoded.material=1
		elif decoded.shape==1 and decoded.material==0:
			appearance=2 if (exterior and cell.y==4) or (cell.x in [0,10,28,38] and cell.z in [0,12,30]) else 1
		a.cells[cell]=blocks.encode_block(decoded.shape,decoded.rotation,decoded.material,appearance)
	furnish()
	var records:=PackedInt32Array(); var positions: Array=a.cells.keys(); positions.sort_custom(func(p: Vector3i,q: Vector3i):return p.x<q.x if p.x!=q.x else (p.z<q.z if p.z!=q.z else p.y<q.y))
	for point: Vector3i in positions: records.append_array(PackedInt32Array([point.x,point.y,point.z,a.cells[point]]))
	var asset: Resource=ClassDB.instantiate("NativeBlockPrefab")
	if not asset.configure(records) or not asset.configure_model_attachments(a.attachments): return null
	var envelope: AABB=asset.get_bounds()
	for attachment: Dictionary in a.attachments:
		if not Packs.objects.has(attachment.model): continue
		var row: Dictionary=Packs.objects[attachment.model]; var mesh: Mesh=load(row.directory+"/models/"+row.id+".tres")
		envelope=envelope.merge(attachment.transform*mesh.get_aabb())
		for box: AABB in mesh.get_meta("collision_boxes"): envelope=envelope.merge(attachment.transform*box)
	if not asset.configure_attachment_envelope(envelope.grow(.01)): return null
	asset.resource_name="Homestead Manor · Courtyard mansion R2"
	asset.set_meta("review_only",true); asset.set_meta("review_revision",2); asset.set_meta("finished_grade",1.0)
	asset.set_meta("description","Two-storey courtyard mansion / furnished kitchen, dining room, library, salon, workshop, utility, baths and bedroom suites")
	asset.set_meta("homestead_items",PackedInt32Array(used.keys())); asset.set_meta("furnishing_layout",furniture)
	asset.set_meta("stair_routes",a.routes); asset.set_meta("door_routes",a.doors); asset.set_meta("room_labels",a.rooms)
	asset.set_meta("entrances",PackedVector3Array([Vector3(19,1,35),Vector3(8,1,34),Vector3(31,1,34)]))
	asset.set_meta("lot_clearance",asset.get_bounds().grow(2)); asset.set_meta("asset_license","CC0-1.0")
	return asset

func furnish() -> void:
	# Kitchen / pantry. Work surfaces stay along the walls, leaving the centre clear.
	a.sign_room("KITCHEN & PANTRY",Vector3(5,3,7))
	for x in [2.1,4.0,5.9]: prop(723,Vector3(x,1,1.75),PI)
	prop(724,Vector3(8.9,1,2),PI); prop(725,Vector3(2,1,5),-PI/2); prop(726,Vector3(2,1,8),-PI/2)
	prop(760,Vector3(8.8,1,4.2),PI/2)
	prop(761,top(723,Vector3(2.1,1,1.75))); prop(762,top(723,Vector3(4,1,1.75))); prop(764,top(723,Vector3(5.9,1,1.75)))
	prop(763,top(726,Vector3(2,1,8))+Vector3(.16,0,.19),.5); prop(765,Vector3(4,2.55,1.14),PI); prop(766,Vector3(6.2,2.4,1.02),PI)
	prop(767,Vector3(8.4,1,8.8)); prop(768,top(723,Vector3(5.9,1,1.75))+Vector3(.1,0,.32)); prop(769,Vector3(9.4,1,9.6))
	prop(737,top(723,Vector3(4,1,1.75))+Vector3(.75,0,.1)); prop(738,top(723,Vector3(2.1,1,1.75))+Vector3(.72,0,.15))
	# Dining: two round conversation tables, china and serving pieces.
	a.sign_room("DINING ROOM",Vector3(33,3,7))
	for point: Vector3 in [Vector3(31.5,1,5),Vector3(35,1,8.5)]:
		prop(810,point)
		for direction in 4:
			var yaw:=direction*PI/2; prop(811,point+Vector3(sin(yaw),0,cos(yaw))*1.05,yaw)
	prop(812,Vector3(34.5,1,1.65),PI); prop(813,Vector3(36.8,1,4),PI/2)
	prop(814,top(810,Vector3(31.5,1,5))); prop(818,top(810,Vector3(35,1,8.5)))
	prop(783,Vector3(29,1,2.4),-PI/2)
	var side:=top(783,Vector3(29,1,2.4)); prop(815,side+Vector3(0,0,-.35)); prop(816,side+Vector3(0,0,.25),PI/2)
	prop(817,top(813,Vector3(36.8,1,4)),PI/2); prop(819,Vector3(36.6,1,10.3))
	# Arrival hall with useful furniture grouped off the circulation route.
	a.sign_room("RECEPTION HALL",Vector3(23,3,8))
	prop(790,Vector3(24.8,1,11.2)); prop(791,Vector3(13.5,1,10)); prop(792,Vector3(13.5,1,7.5))
	prop(793,Vector3(22,1,11.4)); prop(794,Vector3(19,1.01,13.4)); prop(795,Vector3(24.7,2.4,11.98))
	prop(796,Vector3(22,2,13.20),PI); prop(797,Vector3(13.6,1,8.5)); prop(798,Vector3(15.2,1,16.4)); prop(798,Vector3(23.8,1,16.4)); prop(799,Vector3(23.5,1,15.5))
	prop(734,Vector3(25.8,1,10.8)); prop(733,Vector3(25,3,11.83)); prop(732,Vector3(12.02,2.4,4),-PI/2)
	# Utility and washroom, deliberately away from the dining/sitting wing.
	a.sign_room("LAUNDRY & UTILITY",Vector3(5,3,17))
	prop(747,Vector3(2,1,16),-PI/2); prop(748,Vector3(3.25,1,16.3)); prop(749,Vector3(1.4,1,20),-PI/2)
	prop(735,Vector3(2,1,18.5)); prop(736,Vector3(4,1,19.6)); prop(744,top(736,Vector3(4,1,19.6)))
	# Workshop has a clear service entrance and a bench with tools at real height.
	a.sign_room("WORKSHOP",Vector3(5,3,26))
	var bench:=Vector3(3.3,1,22.65); prop(750,bench,PI); prop(751,top(750,bench)+Vector3(-.5,0,0),PI)
	prop(752,Vector3(3.3,2.65,22.02),PI); prop(753,top(750,bench)+Vector3(.6,0,0))
	prop(754,Vector3(3,1,26)); prop(755,Vector3(1.7,1,28),-PI/2); prop(756,Vector3(4,1,28))
	prop(757,Vector3(8.7,1,23)); prop(758,Vector3(8.6,1,25)); prop(759,Vector3(6,1,28),PI/2)
	# Library / communications study.
	a.sign_room("LIBRARY & STUDY",Vector3(34,3,17))
	var desk:=Vector3(35.5,1,14.5); prop(770,desk,PI); prop(771,desk+Vector3(0,0,1.2),PI)
	var worktop:=top(770,desk); prop(772,worktop); prop(774,worktop+Vector3(.55,0,.12)); prop(776,worktop+Vector3(-.55,0,0))
	prop(775,Vector3(37,1,18)); prop(778,Vector3(35,1,15.7)); prop(779,Vector3(37.2,1,14.7))
	prop(777,Vector3(37.98,2.3,16),PI/2); prop(782,Vector3(34.5,1,20.3)); prop(782,Vector3(36.4,1,20.3))
	# Salon faces the courtyard and feels occupied, with reading and music corners.
	a.sign_room("GARDEN SALON",Vector3(33,3,26))
	prop(727,Vector3(34,1,28.6)); prop(780,Vector3(31.2,1,25.6),-.6); prop(780,Vector3(36.7,1,25.6),.6)
	prop(730,Vector3(34,1.008,26.5)); var coffee:=Vector3(34,1.04,26.1); prop(781,coffee)
	prop(786,top(781,coffee)+Vector3(-.35,0,0)); prop(787,top(781,coffee)+Vector3(.40,0,0)); prop(729,top(781,coffee)+Vector3(.55,0,.25))
	prop(789,Vector3(34.5,1,22.55),PI); prop(788,Vector3(37.2,1,29.4)); prop(785,Vector3(29.3,1,23.1))
	var music:=Vector3(29.55,1,26.5); prop(783,music,-PI/2); prop(784,top(783,music),-PI/2)
	prop(773,Vector3(36.5,1,23)); prop(728,top(790,Vector3(24.8,1,11.2))+Vector3(.3,0,0))
	# Upper private suite: bed, bedside light, dressing furniture and real floor space.
	a.sign_room("PRINCIPAL BEDROOM",Vector3(5,7,26))
	var bed:=Vector3(3.9,5,26.7); prop(720,bed); prop(721,Vector3(2.3,5,28)); prop(721,Vector3(5.5,5,28))
	prop(739,top(721,Vector3(2.3,5,28))); prop(807,top(721,Vector3(5.5,5,28)))
	prop(806,top(720,bed)+Vector3(0,0,-.7)); prop(808,top(721,Vector3(5.5,5,28))+Vector3(.18,0,.12)); prop(805,Vector3(7.5,5,26))
	prop(800,Vector3(2.2,5,22.60),PI); prop(801,Vector3(2,5,24),-PI/2); prop(802,Vector3(3.2,5,24),-PI/2)
	prop(803,top(801,Vector3(2,5,24)),-PI/2); prop(809,top(800,Vector3(2.2,5,22.60)))
	prop(804,Vector3(8.5,5,23),.4); prop(731,Vector3(3,6.2,29.70))
	# Private bath and dressing room.
	a.sign_room("BATHROOM",Vector3(5,7,17))
	prop(740,Vector3(2.4,5,16),-PI/2); prop(741,Vector3(2,5,19.4)); prop(725,Vector3(6,5,13.8),PI)
	prop(742,Vector3(6,6.5,13.14),PI); prop(743,Vector3(1.14,6.2,17.8),-PI/2)
	prop(745,top(725,Vector3(6,5,13.8))+Vector3(.38,0,0)); prop(746,Vector3(1.20,5.7,19),-PI/2)
	a.sign_room("DRESSING ROOM",Vector3(6,7,7))
	for x in [2.2,4.2,6.2,8.2]: prop(722,Vector3(x,5,1.8),PI)
	prop(791,Vector3(4.5,5.04,7)); prop(730,Vector3(5.5,5.01,7))
	# Guest suite and upper sitting room use repeats, not empty placeholder rooms.
	a.sign_room("UPPER SITTING ROOM",Vector3(33,7,7))
	prop(727,Vector3(34,5,9.5)); prop(781,Vector3(34,5.04,7.7)); prop(780,Vector3(31.3,5,7),-PI/2)
	prop(782,Vector3(36.8,5,2),PI); prop(798,Vector3(29.5,5,2)); prop(730,Vector3(34,5.01,7.8))
	for back in [13,22]:
		a.sign_room("GUEST BEDROOM",Vector3(34,7,back+4))
		prop(720,Vector3(35.2,5,back+4.5)); prop(721,Vector3(33.6,5,back+5.4)); prop(739,top(721,Vector3(33.6,5,back+5.4)))
		prop(722,Vector3(36.8,5,back+1),PI); prop(800,Vector3(30,5,back+1),PI)
	# Distinct quiet gallery overlooking the entrance courtyard.
	a.sign_room("UPPER GALLERY",Vector3(23,7,8))
	for point: Vector3 in [Vector3(23.8,5,4),Vector3(23.8,5,9)]: prop(780,point,PI/2)
	prop(782,Vector3(13,5,1.7),PI); prop(782,Vector3(15,5,1.7),PI)
	# A bounded service-yard scatter uses the same layout tool as Dev Objects.
	var excluded: Array[AABB]=[AABB(Vector3(0,-1,-2),Vector3(41,16,39))]
	for candidate: Dictionary in preload("res://addons/structures/outdoor_scatter.gd").proposals(170310,Vector3(-5,0,25),5,20,excluded):
		prop(candidate.item,candidate.transform.origin,candidate.transform.basis.get_euler().y)
