# SPDX-License-Identifier: 0BSD
extends SceneTree
const Sites=preload("res://addons/exploration/watchtower_sites.gd")
const Plan=preload("res://addons/world_runtime/custom_world_plan.gd")
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var folder:="res://.build/watchtower_plan"
	DirAccess.make_dir_recursive_absolute(folder)
	var world:=Plan.build(1703,29,Recipe.DEFAULTS,folder)
	check(world.get("ok",false),"ordinary approved seed-1703 district and regional road plan is available")
	if not world.get("ok",false):print(world);quit(1);return
	check(world.get("watchtowers",{}).get("sites",[]).size()==2,"ordinary generation includes two lookouts without a review switch")
	var cached:=Plan.build(1703,29,Recipe.DEFAULTS,folder)
	check(cached.get("cache_hit",false) and cached.watchtowers==world.watchtowers,"binary plan cache retains exact lookout geometry and approaches")
	var roads:Array=world.network.segments.duplicate()
	var reservations:Array=[]
	for district:Dictionary in world.sites:
		roads.append_array(district.roads)
		for lot:Dictionary in district.lots:reservations.append(Rect2(Vector2(lot.bounds.position.x,lot.bounds.position.z),Vector2(lot.bounds.size.x,lot.bounds.size.z)).grow(12))
	for location:Dictionary in world.get("exploration",{}).get("sites",[]):reservations.append(Rect2(Vector2(location.bounds.position.x,location.bounds.position.z),Vector2(location.bounds.size.x,location.bounds.size.z)).grow(12))
	var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,29]))
	var revision:int=core.execute(Codec.command(0)).decode_u32(12)
	var result:=Sites.build(core,roads,reservations,1703)
	check(result.get("ok",false) and result.get("sites",[]).size()==2,"two separated watchtowers fit near actual regional roads")
	print("WATCHTOWER_SITING_RESULT ",result)
	check(core.execute(Codec.command(0)).decode_u32(12)==revision,"siting never mutates the world")
	check(result.get("attempts",193)<=Sites.MAX_ATTEMPTS,"bounded candidate budget")
	for invalid:Dictionary in [{"half_width":"wide"},{"half_width":NAN},{"coefficients":PackedFloat64Array([0,0,0,0]),"curve_index":1<<40},{"coefficients":PackedFloat64Array([0,0,0,0]),"curve_index":.5},{"coefficients":PackedFloat64Array([0,0,0,0,0,0,NAN,0]),"curve_index":0}]:
		var road:Dictionary=roads[0].duplicate();road.merge(invalid,true)
		var rejected:=preload("res://addons/structures/terrain_lot_planner.gd").plan(core,Vector3(1000,0,1000),[road],0,[{"asset":Sites.asset(),"origin":Vector3i(900,40,900),"rotation":0,"street_z":850.,"label":"validation","general_access":true}])
		check(not rejected.get("ok",false) and rejected.get("reason","") in ["Invalid lot road width type","Invalid lot road width","Invalid lot road curve section","Invalid lot curve index type","Nonfinite lot road curve"],"malformed road geometry rejects before survey: "+str(rejected))
	for site:Dictionary in result.get("sites",[]):
		check(site.quality.status=="pass" and site.access_quality.status=="pass","shared foundation and full-width approach budgets pass")
		check(Sites.clear(site.bounds.grow(8),reservations),"existing districts and underground sites remain protected")
	FileAccess.open(folder.path_join("result.bin"),FileAccess.WRITE).store_var(result)
	print("WATCHTOWER_SITING checks=",checks," failures=",failures)
	quit(1 if failures else 0)
