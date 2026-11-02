# SPDX-License-Identifier: 0BSD
extends RefCounted
const Rails=preload("res://addons/structures/mine_rail_catalog.gd")
const ID:="coal_mine"
const STATION_SLOTS:=10
# Local +Z enters the mountain. A timber loading station sits 48 m inside.
static func add_cells(cells:Dictionary,encoder:Node)->void:
	# A real personnel door seals the narrow entrance. Individual timber cells
	# remain independently destructible; the railway is broken at the threshold.
	for x in range(-2,3):
		for y in 4:
			if x==0 and y<2:continue
			cells[Vector3i(x,y,4)]=encoder.encode_block(1,0,1,3)
	# Loading-station canopy, posts and two low sorting benches. The mine floor
	# remains editable terrain and the central rail/walking aisle stays open.
	for x in [-6,6]:
		for z in [47,51,55]:
			for y in 5:cells[Vector3i(x,y,z)]=encoder.encode_block(5,0,1,3)
	for x in range(-6,7):
		for z in range(46,57):cells[Vector3i(x,5,z)]=encoder.encode_block(2,0,1,3)
	for x in [-5,5]:
		for z in [48,52,54]:cells[Vector3i(x,0,z)]=encoder.encode_block(2,0,1,3)
static func attachments()->Array:
	var result:Array=[{"model":"architecture/wooden_door/v1","transform":Transform3D(Basis.IDENTITY.scaled(Vector3(1,2.0/2.2,1)),Vector3(0,0,4.5))}]
	add_rail(result,"short",Vector3(.5,0,.5),0)
	add_rail(result,"short",Vector3(.5,0,6.5),0)
	for z in [8.5,12.5,16.5,20.5,24.5,28.5]:add_rail(result,"turnout" if z==16.5 else "straight",Vector3(.5,0,z),0)
	add_rail(result,"curve",Vector3(.5,0,32.5),0)
	for x in [-3.5,-7.5,-11.5]:add_rail(result,"straight",Vector3(x,0,36.5),-PI*.5)
	add_rail(result,"curve",Vector3(-15.5,0,36.5),-PI*.5)
	for z in [32.5,28.5,24.5]:add_rail(result,"straight",Vector3(-19.5,0,z),PI)
	add_rail(result,"curve",Vector3(-19.5,0,20.5),PI)
	for x in [-15.5,-11.5,-7.5]:add_rail(result,"straight",Vector3(x,0,16.5),PI*.5)
	for z in [38.5,42.5,46.5,50.5,54.5]:add_rail(result,"straight",Vector3(.5,0,z),0)
	for position:Vector3 in [Vector3(3,0,31),Vector3(-22,0,29),Vector3(-3,0,57),Vector3(4,0,59)]:
		result.append({"model":preload("res://addons/exploration/coal_resource.gd").KEY,"transform":Transform3D(Basis.IDENTITY,position)})
	return result
static func add_rail(result:Array,part:String,position:Vector3,yaw:float)->void:
	result.append({"model":Rails.key(part),"transform":Transform3D(Basis(Vector3.UP,yaw),position)})
static func mesh_for(key:String)->Mesh:
	if key==preload("res://addons/exploration/coal_resource.gd").KEY:return preload("res://addons/exploration/coal_resource.gd").mesh()
	if key=="architecture/wooden_door/v1":return load("res://addons/structures/prefabs/door_model.tres")
	for part:String in Rails.PARTS:
		if key==Rails.key(part):return Rails.mesh(part)
	return null
