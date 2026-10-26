extends SceneTree
class Cover extends "res://addons/world_ecosystem/ground_cover.gd":
	var retired:Array[Vector2i]=[]
	func _retire(key:Vector2i)->void:retired.append(key)
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
	var cover:=Cover.new()
	for index:int in range(24):
		var key:=Vector2i(index,0)
		cover.resident[key]=[];cover._dirty[key]=true;cover._resident_layers[key]=16;cover._retiring[key]=true
	cover._wanted[Vector2i(0,0)]=true
	cover._advance_retirement()
	check(cover.retired.size()<=2 and cover.resident.size()>=22,"one frame retires at most two native cover owners")
	check(cover.resident.has(Vector2i(0,0)) and not cover.retired.has(Vector2i(0,0)),"returning to a wanted owner cancels its pending retirement")
	var retained:=Vector2i(20,0);cover._wanted[retained]=true
	for frame:int in range(24):cover._advance_retirement()
	check(cover._retiring.is_empty() and cover.resident.size()==2 and cover.retired.size()==22,"deferred native retirement drains without losing wanted owners")
	check(cover._dirty.size()==2 and cover._resident_layers.size()==2,"retirement releases matching derived owner bookkeeping")
	cover.free()
	print("GROUND_COVER_RETIREMENT failures=",failures);quit(1 if failures else 0)
