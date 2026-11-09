# SPDX-License-Identifier: 0BSD
extends SceneTree
const BAKE=preload("res://addons/player_runtime/assets/debris_geometry.res")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld")
	var shapes:Dictionary=BAKE.get_meta("shapes")
	check(shapes.size()==704,"binary debris catalog covers every supported shape and rotation")
	var valid:=true
	for key:Vector2i in shapes:
		valid=valid and shapes[key] is ConvexPolygonShape3D and shapes[key].points.size()>=4 and blocks.encode_block(key.x,key.y,0)>0
	check(valid,"all baked records have valid physical convex geometry")
	for shape in [1,3,6,7,9,16,25,36]:
		for rotation in [0,1,13]:
			var key:=Vector2i(shape,rotation)
			if not shapes.has(key):continue
			var old:ConvexPolygonShape3D=blocks.preview_mesh(shape,rotation).create_convex_shape(true,true)
			var a:Array=Array(old.points);var b:Array=Array(shapes[key].points);a.sort();b.sort()
			check(a==b,"baked convex vertices equal the previous runtime recipe: %s"%key)
	blocks.free();print("DEBRIS_GEOMETRY failures=",failures);quit(1 if failures else 0)
