# SPDX-License-Identifier: 0BSD
extends RefCounted

class Author:
	extends RefCounted
	var blocks:Node
	var cells:Dictionary={}
	func _init(owner:Node)->void:blocks=owner
	func cell(position:Vector3i,shape:int=1,rotation:int=0,material:int=1,appearance:int=3)->void:
		cells[position]=blocks.encode_block(shape,rotation,material,appearance)
	func area(rect:Rect2i,height:int,shape:int=1,material:int=1,appearance:int=3)->void:
		for column in range(rect.position.x,rect.end.x):
			for row in range(rect.position.y,rect.end.y):cell(Vector3i(column,height,row),shape,0,material,appearance)

static func build(blocks:Node)->Resource:
	var author:=Author.new(blocks)
	author.area(Rect2i(0,0,7,9),0,1,2,2)
	for column in [0,6]:
		for row in [0,4,8]:
			for height in range(1,10):author.cell(Vector3i(column,height,row),5)
	author.area(Rect2i(1,4,5,3),3,8)
	for step in 3:
		for column in [1,2]:author.cell(Vector3i(column,1+step,1+step),3)
		for column in [4,5]:author.cell(Vector3i(column,4+step,3-step),3,2)
	author.area(Rect2i(0,0,7,9),6,8)
	for column in [4,5]:
		for row in range(1,4):author.cells.erase(Vector3i(column,6,row))
		author.cell(Vector3i(column,6,1),3,2)
	for row in range(1,8):
		author.cell(Vector3i(0,7,row),9,16)
		author.cell(Vector3i(6,7,row),9,20)
	for column in range(1,6):
		author.cell(Vector3i(column,7,0),9,4)
		author.cell(Vector3i(column,7,8),9,12)
	for row in range(1,4):author.cell(Vector3i(3,7,row),9,20)
	for column in [4,5]:author.cell(Vector3i(column,7,4),9,4)
	for row in range(4,7):
		author.cell(Vector3i(0,4,row),9,16)
		author.cell(Vector3i(6,4,row),9,20)
	for column in range(1,6):author.cell(Vector3i(column,4,6),9,12)
	for row in [4,8]:
		for column in range(1,4 if row==4 else 6):author.cell(Vector3i(column,6,row),1)
	for column in range(-1,8):
		var step:=4-absi(column-3)
		var height:=10+step/2
		var phase:=step%2
		var rotation:=0 if column<=3 else 2
		for row in range(-1,10):
			author.cell(Vector3i(column,height,row),22 if column==3 else 19+phase,rotation,1,5)
			if phase==0:author.cell(Vector3i(column,height-1,row),23 if column==3 else 21,rotation,1,5)
	for column in [0,6]:
		author.cell(Vector3i(column,4,4))
		for row in [0,4,8]:
			for height in [6,7]:author.cell(Vector3i(column,height,row))
			author.cell(Vector3i(column,10,row),33,0 if column==0 else 2,1,5)
	for column in range(7):author.cell(Vector3i(column,3,4))
	var records:=PackedInt32Array()
	for cell:Vector3i in author.cells:records.append_array(PackedInt32Array([cell.x,cell.y,cell.z,author.cells[cell]]))
	var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
	if not asset.configure(records):return null
	if not asset.configure_model_attachments([{"model":"storage/wooden_chest/v1","transform":Transform3D(Basis.IDENTITY,Vector3(1.8,7,6.3))}]):return null
	asset.resource_name="Wilderness lookout / W1"
	asset.set_meta("content_id","watchtower_w1")
	asset.set_meta("site_surface_offset",1)
	asset.set_meta("site_sample_band",1)
	asset.set_meta("site_entrance",Vector3(1.5,1,-.5))
	asset.set_meta("description","Timber lookout with two stair flights, sheltered observation deck and supplies")
	asset.set_meta("walk_route",PackedVector3Array([Vector3(1.5,1.02,.5),Vector3(1.5,4.02,4.7),Vector3(4.8,4.02,4.7),Vector3(4.8,7.02,.55),Vector3(2.5,7.02,.55),Vector3(2.5,7.02,5),Vector3(4.5,7.02,6.5)]))
	asset.set_meta("sleeper",Vector3(4.5,7,6.5))
	return asset
