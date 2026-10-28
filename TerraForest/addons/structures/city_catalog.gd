extends RefCounted

const IDS:=["storage_s1","police_p1","medical_h1","research_r1","factory_f1","apartments_a3"]
const TITLES:=["Storage warehouse","Police station","Medical centre","Pharmaceutical research","Factory","Apartments"]

static func asset(index:int)->Resource:
	if index<0 or index>=IDS.size():return null
	var source:Resource=load("res://addons/structures/prefabs/city_"+IDS[index]+".tres")
	return source.duplicate() if source!=null else null

static func recipe(center:Vector3)->Array:
	var result:=[]
	var choices:=[0,4,3,1,2,5]
	for index in choices.size():
		var prefab:Resource=asset(choices[index])
		var bounds:AABB=prefab.placement_bounds(Vector3i.ZERO,0)
		var street:float=center.z+[-64,0,64][index/2]
		var target:=Vector3(center.x+(-32 if index%2==0 else 32),0,street-27)
		var origin:=Vector3i(roundi(target.x-bounds.get_center().x),0,roundi(target.z-bounds.get_center().z))
		result.append({"asset":prefab,"origin":origin,"rotation":0,"street_z":street,"label":TITLES[choices[index]]})
	return result

static func streets(center:Vector3)->Array:
	var result:=[]
	var lots=preload("res://addons/structures/northern_lots.gd")
	for row in [-64,0,64]:result.append(lots._segment(center+Vector3(-64,0,row),center+Vector3(64,0,row),4,3,4,0,4))
	for column in [-64,64]:result.append(lots._segment(center+Vector3(column,0,-64),center+Vector3(column,0,64),4,3,4,0,4))
	return result
