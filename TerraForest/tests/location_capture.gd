# SPDX-License-Identifier: 0BSD
extends SceneTree
const Capture=preload("res://addons/world_runtime/location_capture.gd")
const Generation=preload("res://addons/exploration/generation.gd")
var checks:=0
var failures:=0

func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func run()->void:
	var layouts:Array=Generation.Layouts.load_catalog()
	for layout:Dictionary in layouts:
		var asset:Resource=Generation.Layouts.prefab(layout)
		for rotation in 4:
			var origin:=Vector3i(900,70,1100)
			var bounds:=Generation.location_bounds(asset,layout,origin,rotation,false)
			check(Capture.valid_bounds(bounds),layout.id+" integer bounded capture, rotation "+str(rotation))
			check(bounds.encloses(asset.placement_bounds(origin,rotation)),layout.id+" includes structural/model envelope "+str(rotation))
			var enclosed:=true
			for segment:Dictionary in Generation.Layouts.segments(layout,origin,rotation):enclosed=enclosed and bounds.encloses(segment.bounds)
			check(enclosed,layout.id+" includes entire excavation "+str(rotation))
	for size:Vector3i in [Vector3i.ONE,Vector3i(65,12,130),Vector3i.ONE*129,Vector3i.ONE*256]:
		var boxes:Array=[];var volume:=0;var valid:=true
		for tile:Array in Capture.tiles(Vector3i(12,4,100),size):
			var box:=AABB(Vector3(tile[0]),Vector3(tile[1]))
			valid=valid and AABB(Vector3(12,4,100),Vector3(size)).encloses(box) and tile[1].x<=64 and tile[1].y<=64 and tile[1].z<=64
			for other:AABB in boxes:valid=valid and not box.intersects(other)
			boxes.append(box);volume+=tile[1].x*tile[1].y*tile[1].z
		check(valid and volume==size.x*size.y*size.z,"nonoverlapping complete bounded tiles "+str(size))
	var bounds:=AABB(Vector3(10,20,30),Vector3(7,8,9))
	var root_points:=[Vector3(10,20,30),Vector3(17,20,30),Vector3(10,28,30),Vector3(10,20,39),Vector3(11,19,31),Vector3(11,22,31)]
	var transforms:Array=[]
	for point:Vector3 in root_points:transforms.append(Transform3D(Basis.IDENTITY,point))
	check(Capture.selected_roots({"ids":PackedInt64Array([1,2,3,4,5,6]),"transforms":transforms},bounds)==PackedInt64Array([1,6]),"natural roots use half-open exact three-dimensional ownership")
	var bytes:=Capture.envelope("ground",bounds,[PackedInt64Array(),PackedByteArray([1,2])])
	check(Capture.unpack(bytes,"ground",bounds).records.size()==2,"typed binary owner envelope roundtrip")
	check(Capture.unpack(bytes,"trees",bounds).is_empty() and Capture.unpack(bytes,"ground",bounds.grow(1)).is_empty(),"wrong owner and volume reject")
	check(Capture.unpack(var_to_bytes([2,"ground",bounds,[]]),"ground",bounds).is_empty(),"future envelope version rejects")
	check(not Capture.valid_bounds(AABB(Vector3(0,4,0),Vector3.ONE)) and not Capture.valid_bounds(AABB(Vector3(2,4,2),Vector3.ONE*129)),"world edge and oversized ownership reject without clamping")
	var location:={"key":2,"layout":"test","origin":Vector3i(12,20,32),"rotation":0,"bounds":bounds,"residents":PackedInt64Array([10]),"containers":PackedInt64Array([20]),"completed":0}
	var identity:=Capture.definition(location);location.completed=1
	check(identity==Capture.definition(location),"quest completion never changes original definition identity")
	location.bounds=bounds.grow(1)
	check(identity!=Capture.definition(location),"ownership change changes definition identity")
	print("LOCATION_CAPTURE checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
