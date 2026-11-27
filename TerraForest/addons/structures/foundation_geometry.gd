# SPDX-License-Identifier: 0BSD
extends RefCounted
## Cold admission for generation variants that retain authored rooms exactly.
static func retains_authored_geometry(asset:Resource,reference:Resource)->bool:
	if asset==null or reference==null or asset.get_model_attachments()!=reference.get_model_attachments():return false
	var original:PackedInt32Array=reference.get_records();var actual:PackedInt32Array=asset.get_records()
	if original==actual:return true
	var band:int=reference.get_meta("site_surface_offset",0)
	var declared:int=asset.get_meta("metropolis_foundation_footings",0)
	if band not in [5,9] or declared<=0 or actual.size()!=original.size()+declared*4:return false
	var cells:Dictionary={};var low:Dictionary={}
	for at in range(0,original.size(),4):
		var cell:=Vector3i(original[at],original[at+1],original[at+2]);cells[cell]=original[at+3]
		var column:=Vector2i(cell.x,cell.z);low[column]=mini(int(low.get(column,4096)),cell.y)
	var retained:=0;var added:=0
	for at in range(0,actual.size(),4):
		var cell:=Vector3i(actual[at],actual[at+1],actual[at+2])
		if cells.has(cell):
			if cells[cell]!=actual[at+3]:return false
			retained+=1;continue
		var column:=Vector2i(cell.x,cell.z)
		if not low.has(column) or int(low[column])<=0 or int(low[column])>band or cell.y<0 or cell.y>=int(low[column]) or actual[at+3]!=65:return false
		added+=1
	return retained==cells.size() and added==declared
