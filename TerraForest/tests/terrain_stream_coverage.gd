extends "res://tests/terrain_publication_probe.gd"

func split_to(key:Vector3i)->void:
	for size:int in [32,64,128,256]:
		world.split_state[Vector3i(key.x/size*size,key.y/size*size,size)]=true

func install(key:Vector3i,publish:bool=true)->void:
	world._receive(build(key,0))
	drain()
	if publish:world._update_cut()

func ray(point:Vector3)->Dictionary:
	await physics_frame
	await process_frame
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*300,point-Vector3.UP*100,1)
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func boundary(entry:Dictionary,plane:float)->Dictionary:
	var points:Dictionary={}
	for vertex:Vector3 in entry.arrays[Mesh.ARRAY_VERTEX]:
		if vertex.x>=plane-1 and vertex.x<=plane and vertex.z>entry.key.y+1 and vertex.z<entry.key.y+entry.key.z-1:points[vertex]=true
	return points

func run()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	core=ClassDB.instantiate("TerrainCore")
	recipes=ClassDB.instantiate("NativeTerrainCollision")
	world=Stream.new();root.add_child(world);world.set_process(false)
	world.planner=ClassDB.instantiate("NativeTerrainPlanner")
	world.material=StandardMaterial3D.new();world.world_ready=true
	check(not world.backend.region_terrain,"default renderer is exercised without opting into regional terrain")
	var target:=Vector3i(1296,1248,16)
	var neighbour:=Vector3i(1312,1248,16)
	var parent:=Vector3i(1280,1024,256)
	split_to(target);split_to(neighbour)
	install(target)
	check(world.visible_cut==[target] and world.root_coverage==0,"ready target is exposed without claiming missing root coverage")
	check(world.player_region_ready(Vector3(1308,0,1260)),"ready target activates collision readiness immediately")
	var target_node:Node3D=world.tiles[target].node
	var hit:Dictionary=await ray(Vector3(1308,0,1260))
	check(not hit.is_empty() and hit.get("collider")==world.tiles[target].body,"newly exposed target has matching physical terrain")
	install(parent)
	check(world.visible_cut==[target] and target_node.visible and not world.tiles[parent].node.visible,"late coarse parent cannot withdraw the target or overlap its surface")
	install(neighbour,false)
	world.pending_edit=true;world._update_cut()
	check(world.visible_cut==[target] and not world.tiles[neighbour].active,"in-progress edit keeps the old cut until atomic publication")
	world.pending_edit=false;world._update_cut()
	check(world.visible_cut.has(target) and world.visible_cut.has(neighbour) and not world.visible_cut.has(parent),"ready neighbour joins without waiting for unrelated siblings")
	var target_edge:=boundary(world.tiles[target],1312)
	check(not target_edge.is_empty() and target_edge==boundary(world.tiles[neighbour],1312),"neighbouring fine surfaces share exact native boundary vertices")
	var left:Dictionary=await ray(Vector3(1311.99,0,1260))
	var right:Dictionary=await ray(Vector3(1312.01,0,1260))
	var colliders:Array=[world.tiles[target].body,world.tiles[neighbour].body]
	check(not left.is_empty() and not right.is_empty() and colliders.has(left.get("collider")) and colliders.has(right.get("collider")),"both sides of the grid edge are covered by published fine colliders")
	var distant:=Vector3i(768,1024,256)
	install(distant)
	var distant_node:Node3D=world.tiles[distant].node
	var distant_child:=Vector3i(784,1040,16)
	split_to(distant_child);install(distant_child)
	check(world.visible_cut.has(distant) and not world.visible_cut.has(distant_child) and distant_node.visible,"previously covered root remains intact until all replacement coverage is ready")
	check(world.covered_roots.has(distant) and not world.covered_roots.has(parent),"complete and partial roots retain distinct loading readiness")
	check(not world.player_region_ready(Vector3(788,0,1044)),"hidden fine collision cannot falsely declare an existing coarse region ready")
	world.tiles[distant].dirty=true;world._update_cut()
	check(world.visible_cut.has(distant) and distant_node.visible,"dirty visible parent remains live during edit preparation")
	world.tiles[parent].dirty=true;world._update_cut()
	check(not world.visible_cut.has(parent) and world.tiles[target].node==target_node and target_node.visible,"stale hidden parent cannot resurrect over current fine terrain")
	world.shutdown();world.free();await process_frame
	var folder:=ProjectSettings.globalize_path("res://reports")
	DirAccess.make_dir_recursive_absolute(folder)
	var file:=FileAccess.open(folder.path_join("terrain_stream_coverage.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"checks":checks,"timings":timings,"scope":"Default production stream coverage, native meshes and physics; no scheduling or rendered latency assertion."},"  "));file.close()
	print("TERRAIN_STREAM_COVERAGE failures=",failures)
	quit(1 if failures else 0)
