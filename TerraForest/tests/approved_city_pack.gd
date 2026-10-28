extends SceneTree

const City=preload("res://addons/structures/city_catalog.gd")
var checks:=0
var failures:=0

func _initialize()->void:run.call_deferred()

func check(condition:bool,message:String)->bool:
	checks+=1
	if not condition:failures+=1
	print("PASS " if condition else "FAIL ",message)
	return condition

func run()->void:
	var counts:=[1982,1972,2360,2748,3501,3903]
	for index in City.IDS.size():
		var asset:Resource=City.asset(index)
		if not check(asset!=null,"pack includes "+City.IDS[index]):continue
		check(asset.get_records().size()==counts[index]*4 and not asset.get_model_attachments().is_empty(),"pack retains cells and attached models / "+City.IDS[index])
		check(asset.get_meta("approved_as_addition",false) and asset.get_meta("site_surface_offset",0)==1 and asset.has_meta("site_entrance"),"pack retains approved site metadata / "+City.IDS[index])
	var lots:Array=City.recipe(Vector3(1000,40,1000))
	check(lots.size()==6 and City.streets(Vector3(1000,40,1000)).size()==5,"pack includes complete mixed-use district recipe")
	var prefab:Resource=ClassDB.instantiate("NativeBlockPrefab")
	var road:={"start":Vector3(100,40,100),"finish":Vector3(140,40,100),"half_width":4.0}
	var baseline:Dictionary=prefab.plan_paving([road])
	var access:Dictionary=prefab.plan_paving([road],[Rect2(115,85,5,30)])
	check(baseline.get("ok",false) and access.get("ok",false) and access.tiles<baseline.tiles,"pack native access cutout API matches exported scripts")
	print("APPROVED_CITY_PACK checks=",checks," failures=",failures)
	quit(1 if failures else 0)
