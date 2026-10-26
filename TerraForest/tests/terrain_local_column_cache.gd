extends "res://tests/terrain_worker_publication_probe.gd"

func content(entry:Dictionary)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	var owners:Array=entry.bricks.keys();owners.sort()
	for identity:int in owners:
		var arrays:Array=entry.bricks[identity].arrays
		hash.update(PackedInt32Array([identity]).to_byte_array())
		for channel:int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_INDEX]:hash.update(var_to_bytes(arrays[channel]))
	return hash.finish().hex_encode()

func run()->void:
	var directory:String="user://local_column_cache_%d"%OS.get_process_id()
	var key:=Vector3i(1280,1024,256)
	var expected:String=""
	var results:Array=[]
	for session:int in range(2):
		world=FixedCut.new();root.add_child(world);world.set_process(false)
		world.material=StandardMaterial3D.new();world.backend.cache_path=directory
		check(world.backend.local_terrain and not world.backend.region_terrain,"bounded columns are the production default")
		check(world.backend.start(true)==OK,"isolated cached worker starts")
		check(await pump_until(func():return world.world_ready),"isolated cached world ready")
		world.visible_cut=[key]
		for pass_index:int in range(2):
			var hits:int=world.backend.disk_cache.hits
			var stamp:int=session*2+pass_index
			world.stamps[key]=stamp
			check(world.backend.submit({"kind":"mesh","key":key,"epoch":world.epoch,"stamp":stamp,"base":false}),"cached coarse build admitted")
			check(await pump_until(func():return world.tiles.has(key) and world.tiles[key].stamp==stamp),"cached coarse build published")
			check(world.tiles[key].bricks.size()==64,"cache retains all column identities including empty owners")
			var digest:String=content(world.tiles[key])
			if expected.is_empty():expected=digest
			check(digest==expected,"cached geometry matches cold native construction after worker restart")
			if session>0 or pass_index>0:check(world.backend.disk_cache.hits-hits==64,"all unchanged columns load from the content-addressed cache")
			results.append({"session":session,"pass":pass_index,"hits":world.backend.disk_cache.hits-hits,"writes":world.backend.disk_cache.writes,"bytes":world.cache_bytes,"digest":digest})
		world.shutdown();world.free();await process_frame
	var folder:=ProjectSettings.globalize_path("res://reports")
	DirAccess.make_dir_recursive_absolute(folder)
	var file:=FileAccess.open(folder.path_join("terrain_local_column_cache.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"results":results},"  "));file.close()
	print("TERRAIN_LOCAL_COLUMN_CACHE failures=",failures)
	quit(1 if failures else 0)
