extends SceneTree

const Asset=preload("res://addons/world_ecosystem/woodland_mesh.gd")
var failures:=0
var checks:=0

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func run()->void:
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	var scatter:RefCounted=ClassDB.instantiate("NativeVegetationScatter")
	var ecosystem=preload("res://addons/world_ecosystem/world_ecosystem.gd").new()
	var forest=preload("res://addons/vegetation/vegetation_world.gd").new()
	check(forest.draw_distance==576 and ecosystem.stream_radius==640,"extended forest defaults retain 64m preload margin")
	var maximum:=0
	var missing:=0
	var ordering:=true
	for center in [Vector2i(16,16),Vector2i(0,0),Vector2i(31,31),Vector2i(31,0),Vector2i(0,16)]:
		var wanted:Array=scatter.wanted_cells(center,ecosystem.stream_radius,ecosystem.max_resident_cells,true)
		maximum=maxi(maximum,wanted.size())
		var previous_distance:=-1
		for key:Vector2i in wanted:
			var distance:int=(key-center).length_squared()
			ordering=ordering and distance>=previous_distance and key.x>=0 and key.y>=0 and key.x<32 and key.y<32
			previous_distance=distance
		for offset in [Vector2.ZERO,Vector2(63.99,0),Vector2(0,63.99),Vector2(63.99,63.99),Vector2(32,32)]:
			var eye:Vector2=Vector2(center)*64+offset
			for angle in range(0,360,2):
				for distance in [forest.draw_distance,ecosystem.stream_radius-.01]:
					var point:Vector2=eye+Vector2.from_angle(deg_to_rad(angle))*distance
					var key:=Vector2i(floori(point.x/64),floori(point.y/64))
					if key.x>=0 and key.y>=0 and key.x<32 and key.y<32 and not wanted.has(key):missing+=1
	check(missing==0,"every tested visible/preload direction covered at owner corners and world edges")
	check(maximum==405 and maximum<=ecosystem.max_resident_cells and maximum*36<forest.root_limit,"405 maximum owners fit admission and root budgets")
	check(ordering,"native streaming remains nearest-first and inside world")
	var stable:Dictionary=scatter.candidates(Vector2i(16,16),1703,.82)
	for center in [Vector2i(3,3),Vector2i(27,27),Vector2i(16,16)]:scatter.wanted_cells(center,640,441,true)
	check(stable==scatter.candidates(Vector2i(16,16),1703,.82),"travel and range do not change procedural identities")
	var rows:=[]
	for species in [1,6,7,8]:
		var method:String={1:"fern",6:"bush",7:"twigs",8:"woody_bush"}[species]
		var baseline:=Asset.build(species,true,false)
		var extended:=Asset.build(species)
		check(baseline.get_faces()==extended.get_faces(),"near geometry unchanged species %d"%species)
		var old_asset:=Asset.new();old_asset.call(method,true)
		var far_asset:=Asset.new();far_asset.call(method,true,true)
		check(far_asset.vertices.size()<old_asset.vertices.size()*.65,"far mesh reduces triangles species %d"%species)
		var valid:=true
		for index in range(0,far_asset.vertices.size(),3):
			var first:Vector3=far_asset.vertices[index]
			var second:Vector3=far_asset.vertices[index+1]
			var third:Vector3=far_asset.vertices[index+2]
			valid=valid and first.is_finite() and extended.custom_aabb.has_point(first) and (second-first).cross(third-first).length_squared()>1e-15
		check(valid,"finite nondegenerate distant mesh within original bounds %d"%species)
		rows.append({"species":species,"previous_far_triangles":old_asset.vertices.size()/3,"extended_far_triangles":far_asset.vertices.size()/3})
	forest.free();ecosystem.free()
	print("VEGETATION_EXTENDED_LOD ",JSON.stringify({"checks":checks,"failures":failures,"maximum_owners":maximum,"meshes":rows}))
	print("VEGETATION_EXTENDED_LOD failures=",failures)
	quit(1 if failures else 0)
