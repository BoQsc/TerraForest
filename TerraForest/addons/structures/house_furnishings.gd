# SPDX-License-Identifier: 0BSD
extends RefCounted
## Cold recipe authoring only. Placed objects use the ordinary native batches.
## Existing fabric and attachments are retained, including doors and storage.
const VERSION:=1
var cells:Dictionary={}
var occupied:Array[AABB]=[]
var reserved:Array[AABB]=[]
var additions:Array[Dictionary]=[]
var layout:Array[Dictionary]=[]
var meshes:Dictionary={}
var keys:Dictionary={}
var limits:=AABB()

static func apply(source:Resource,kind:String)->Resource:
	if source==null or source.has_meta("homestead_furnishings"):return source
	if kind not in ["cottage_a2","cottage_legacy","house_c1","apartments_a3","tower","workshop","shop_b1","shop_b2","trader_t1"]:return source
	var author:=new()
	author.prepare(source,kind)
	match kind:
		"cottage_a2":author.cottage()
		"cottage_legacy":author.cottage(1)
		"house_c1":author.house()
		"apartments_a3":author.apartments()
		"tower":author.tower(source)
		_:author.service(source,kind)
	author.table_details(source)
	var result:Resource=source.duplicate()
	var all:Array=source.get_model_attachments();all.append_array(author.additions)
	if not result.configure_model_attachments(all):return null
	result.set_meta("homestead_furnishings",VERSION)
	result.set_meta("homestead_layout",author.layout)
	result.set_meta("homestead_archetype",kind)
	return result

func prepare(source:Resource,kind:String)->void:
	limits=source.placement_bounds(Vector3i.ZERO,0)
	var records:PackedInt32Array=source.get_records()
	for index in range(0,records.size(),4):cells[Vector3i(records[index],records[index+1],records[index+2])]=records[index+3]
	for row:Dictionary in source.get_model_attachments():
		var pose:Transform3D=row.transform
		if row.model=="architecture/wooden_door/v1":
			# Full leaf swing and a capsule-wide approach on both sides.
			reserved.append(pose*AABB(Vector3(-.3,0,-1.15),Vector3(1.6,2.2,2.3)))
		elif row.model.begins_with("furniture/") or row.model=="storage/wooden_chest/v1":
			var name:String=row.model.split("/")[1]
			var path:="res://addons/structures/prefabs/"+("storage_chest" if name=="wooden_chest" else name)+"_model.tres"
			var mesh:Mesh=load(path)
			for box:AABB in mesh.get_meta("collision_boxes",[mesh.get_aabb()]):occupied.append(pose*box)
	# Existing stair and spawn corridors are never furnishing sites.
	for route:Dictionary in source.get_meta("stair_routes",[]):
		var a:Vector3=route.start;var b:Vector3=route.end
		reserved.append(AABB(a.min(b)-Vector3(.5,-.04,.5),(a-b).abs()+Vector3(1,1.85,1)))
	var anchors:Array=[]
	if kind=="cottage_a2":anchors=[Vector3(1.1,2,2.8)]
	if kind=="cottage_legacy":reserved.append(AABB(Vector3(-.3,1,4.4),Vector3(1.6,2.2,2.3)))
	if kind=="house_c1":anchors=[Vector3(2,5,1),Vector3(8,5,2),Vector3(8,5,8),Vector3(.5,9,2)]
	if kind=="apartments_a3":anchors=[Vector3(2,1,2),Vector3(8,5,2),Vector3(20,9,2),Vector3(2,13,8)]
	for point:Vector3 in anchors:reserved.append(AABB(point-Vector3(.65,0,.65),Vector3(1.3,1.9,1.3)))
	if kind=="house_c1":
		for y in [5.0,9.0]:reserved.append(AABB(Vector3(.05,y+.04,-5.8),Vector3(3,1.85,1.2)))
		reserved.append(AABB(Vector3(.05,9.04,.35),Vector3(2.9,1.85,2.1)))
		reserved.append(AABB(Vector3(2.05,9.04,-5.8),Vector3(.9,1.85,8.2)))
		reserved.append(AABB(Vector3(.05,5.04,-5.8),Vector3(.9,1.85,14.8)))
	if kind=="tower":
		# All current tower variants share the middle stair shaft and east aisle.
		reserved.append(AABB(Vector3(-1.6,1,-.6),Vector3(5.2,64,8.3)))

func mesh_for(item:int)->Mesh:
	if not meshes.has(item):
		var pack:int=(item-720)/10+1
		var folder:="homestead_%02d"%pack if item<820 else "outdoor_01"
		var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://addons/structures/packs/"+folder+"/pack.json"))
		var definition:Dictionary=manifest.objects[(item-720)%10]
		meshes[item]=load("res://addons/structures/packs/"+folder+"/models/"+definition.id+".tres")
		keys[item]="packs/"+folder+"/"+str(definition.id)+"/v1"
	return meshes[item]

func fits(parts:Array[AABB],floor_support:bool,feet:float)->bool:
	for original:AABB in parts:
		var box:=original.grow(-.0002)
		if not limits.encloses(original):return false
		for other:AABB in occupied:
			if box.intersects(other.grow(-.0002)):return false
		for other:AABB in reserved:
			if box.intersects(other):return false
		var low:=Vector3i(box.position.floor());var high:=Vector3i(box.end.floor())
		for z in range(low.z,high.z+1):
			for y in range(low.y,high.y+1):
				for x in range(low.x,high.x+1):
					if cells.has(Vector3i(x,y,z)):return false
	if floor_support:
		var bottom:=INF
		for box:AABB in parts:bottom=minf(bottom,box.position.y)
		# Some authored bath/seat proxies begin above their visible feet.
		if bottom-feet>.05:return false
		for box:AABB in parts:
			if absf(box.position.y-bottom)>.02:continue
			for x in [box.position.x+.002,box.end.x-.002]:
				for z in [box.position.z+.002,box.end.z-.002]:
					if not cells.has(Vector3i(floori(x),floori(feet-.02),floori(z))):return false
	return true

func add(item:int,point:Vector3,yaw:float=0,floor_support:bool=true)->Dictionary:
	var mesh:=mesh_for(item)
	var bottom:float=mesh.get_aabb().position.y
	for box:AABB in mesh.get_meta("collision_boxes"):bottom=minf(bottom,box.position.y)
	var pose:=Transform3D(Basis(Vector3.UP,yaw),point-Vector3.UP*bottom)
	var parts:Array[AABB]=[]
	for box:AABB in mesh.get_meta("collision_boxes"):parts.append(pose*box)
	if not fits(parts,floor_support,point.y):return {}
	additions.append({"model":keys[item],"transform":pose});occupied.append_array(parts)
	var record:={"item":item,"position":pose.origin,"rotation":yaw,"floor_supported":floor_support}
	layout.append(record)
	return record

func top(item:int,parent:Dictionary,offset:Vector2=Vector2.ZERO,height:float=-1)->Dictionary:
	if parent.is_empty():return {}
	var surface:float=height if height>=0 else {721:.575,723:.9,750:.895,770:.8025,781:.4325,783:.8325,790:.8325,800:1.015,801:.8425,810:.805}.get(parent.item,0)
	var point:Vector3=parent.position+Basis(Vector3.UP,parent.rotation)*Vector3(offset.x,surface,offset.y)
	return add(item,point,parent.rotation,false)

func bedroom(point:Vector3,variant:int=0)->void:
	add(720,point,PI)
	var bedside:=add(721,point+Vector3(1.18,0,-.55))
	top(807 if variant%2==0 else 739,bedside)
	add(722 if variant%2==0 else 800,point+Vector3(-.15,0,2.35))
	add(805 if variant%2==0 else 735,point+Vector3(1.25,0,1.3))

func kitchen(point:Vector3)->void:
	var counter:=add(723,point)
	top(764,counter,Vector2(-.25,0));top(767,counter,Vector2(.32,0))
	add(725,point+Vector3(1.2,0,0));add(726,point+Vector3(-1.1,0,0));add(760,point+Vector3(-2,0,0))
	add(769,point+Vector3(-2,0,1))

func sitting(point:Vector3,variant:int=0)->void:
	add(727 if variant%2==0 else 780,point)
	var table:=add(781,point+Vector3(0,0,1.25))
	top(786 if variant%2==0 else 787,table)
	add(788,point+Vector3(1.45,0,0))
	add(785,point+Vector3(-1.3,0,0))

func cottage(floor_y:float=2)->void:
	# Rear sleeping corner, right-hand kitchen, front sitting area; centre aisle open.
	bedroom(Vector3(-1.7,floor_y,-2.8))
	add(722,Vector3(-2.3,floor_y,3.5))
	kitchen(Vector3(1.4,floor_y,-3.5))
	add(780,Vector3(2.6,floor_y,2.3),PI)
	var table:=add(781,Vector3(2.4,floor_y,3.6));top(787,table)
	add(734,Vector3(-2.7,floor_y,2));add(793,Vector3(-1.8,floor_y,4.5))
	add(798,Vector3(.95,floor_y,6.35));add(797,Vector3(-.8,floor_y,6.45))

func house()->void:
	# Basement stores/workshop, ground-floor sitting/kitchen and upstairs bedroom.
	var bench:=add(750,Vector3(1.8,1,-5.5));top(751,bench,Vector2(-.5,0));top(753,bench,Vector2(.4,0))
	add(755,Vector3(3.9,1,-2.5),PI*.5);add(758,Vector3(3.9,1,1))
	add(747,Vector3(-3,1,-3.9));add(749,Vector3(-3.9,1,1.6))
	var counter:=add(723,Vector3(-3,5,-4.7));top(764,counter,Vector2(-.25,0));top(767,counter,Vector2(.32,0))
	add(725,Vector3(-1.65,5,-4.7));add(726,Vector3(-3.5,5,-3.5));add(760,Vector3(-3.4,5,-1.1))
	sitting(Vector3(2.9,5,1.1))
	add(782,Vector3(-3.8,5,1.4),PI*.5)
	add(780,Vector3(-2.6,5,1.5))
	bedroom(Vector3(3.8,9,1.2),1)
	var bedside:=add(721,Vector3(4.45,9,2.8));top(807,bedside)
	var desk:=add(770,Vector3(2.8,9,-5.8));top(772,desk);add(771,Vector3(2.8,9,-4.6),PI)
	add(741,Vector3(-3.3,9,-2.4));add(740,Vector3(-3,9,5.5),PI*.5)
	add(791,Vector3(-2.4,9,9.4),PI);add(798,Vector3(2.7,9,9.4));add(799,Vector3(1.7,9,9.4))
	# Garage edges preserve the parked vehicle/departure corridor at x=9.5.
	add(825,Vector3(6.65,5,-.6));add(821,Vector3(11.7,5,6.3));add(822,Vector3(6.6,5,1.5))

func apartments()->void:
	for level in 4:
		for side in 2:
			for back in 2:
				var anchor:=Vector3(0 if side==0 else 13,1+level*4,back*10)
				var variant:=level+side+back
				bedroom(anchor+Vector3(7.4,0,2.2),variant)
				# Some apartments retain a sleeper reservation at the first corner.
				var has_bed:=false
				for placed:Dictionary in layout:
					if placed.item==720 and is_equal_approx(placed.position.y,anchor.y) and placed.position.x>=anchor.x and placed.position.x<anchor.x+9 and placed.position.z>=anchor.z and placed.position.z<anchor.z+10:has_bed=true
				if not has_bed:add(720,anchor+Vector3(1.85,0,4.7),PI)
				kitchen(anchor+Vector3(2.2,0,8.5))
				add(780,anchor+Vector3(7.7,0,8),PI)
				add(779,anchor+Vector3(1.6,0,6.6))
				add(790,anchor+Vector3(7.8,0,5.2),PI*.5)
				add(794,anchor+Vector3(8.3 if side==0 else 1.65,0,7.6))

func tower(source:Resource)->void:
	var levels:=0
	for cell:Vector3i in cells:levels=maxi(levels,cell.y)
	for floor_index in maxi(1,levels/4):
		var y:=1.0+floor_index*4
		bedroom(Vector3(-5,y,2.5),floor_index)
		kitchen(Vector3(3.6,y,-6.3))
		sitting(Vector3(5.3,y,.5),floor_index)
		var desk:=add(770,Vector3(-5,y,-6.3));top(773,desk,Vector2(-.3,0));top(776,desk,Vector2(.3,0))
		add(771,Vector3(-5,y,-5.2),PI)
		add(741,Vector3(7.6,y,5));add(740,Vector3(5.6,y,6.8));add(749,Vector3(-6.6,y,5.3))

func service(source:Resource,kind:String)->void:
	# Add tools, kitchen stock and office details to existing work surfaces.
	var index:=0
	for row:Dictionary in source.get_model_attachments():
		if row.model!="furniture/table/v1":continue
		var pose:Transform3D=row.transform
		var items:=[753,756,757,776] if kind=="workshop" else [738,767,768,814,818,816]
		add(items[index%items.size()],pose*Vector3(0,.8,0),0,false)
		index+=1

func table_details(source:Resource)->void:
	var index:=0
	for row:Dictionary in source.get_model_attachments():
		if row.model!="furniture/table/v1":continue
		var pose:Transform3D=row.transform
		add([729,738,776,814,818][index%5],pose*Vector3(-.38,.8,0),0,false)
		add([728,737,787,817,816][index%5],pose*Vector3(.38,.8,0),0,false)
		index+=1
