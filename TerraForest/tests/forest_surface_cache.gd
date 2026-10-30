# SPDX-License-Identifier: 0BSD
extends SceneTree

const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
	var cache_path:=""
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--derived-cache="):cache_path=argument.trim_prefix("--derived-cache=")
	if cache_path.is_empty():push_error("Owned cache required");quit(1);return
	var backend=load("res://addons/volumetric_terrain/terrain_backend.gd").new()
	backend.native=ClassDB.instantiate("TerrainCore")
	backend.native.execute(Codec.command(6,[1703,1]))
	backend.disk_cache.minimum_free_bytes=0
	backend.disk_cache.configure("surface-test-v1","snapshot",0,cache_path)
	var points:=PackedVector3Array([Vector3(101,0,105),Vector3(117,0,109)])
	var job:={"points":points,"cache_owner":Vector2i(1,1),"token":1,"epoch":1,"revision":1}
	backend._execute_surface_batch(job)
	var original:Dictionary=backend.poll()[0]
	check(original.points.size()==2 and backend.disk_cache.writes==1,"cold surface page writes checked binary result")
	backend._execute_surface_batch(job)
	check(backend.poll()[0]==original and backend.disk_cache.hits==1,"warm surface page returns byte-identical points and normals")
	var saved:PackedByteArray=backend.native.execute(Codec.command(4))
	var surface:Vector3=original.points[0]
	backend.native.execute(Codec.brush(surface,surface,3,0,false,1))
	backend._execute_surface_batch(job)
	var edited:Dictionary=backend.poll()[0]
	check(backend.disk_cache.writes==2 and backend.disk_cache.hits==1 and edited.points!=original.points,"local density edit changes dependency and rejects stale support")
	backend.native.execute(Codec.command(3,[1800,80,1800,1]))
	backend._execute_surface_batch(job)
	check(backend.poll()[0]==edited and backend.disk_cache.hits==2,"remote edit reuses unchanged owner page")
	backend.active_input=true
	var hits:int=backend.disk_cache.hits;var writes:int=backend.disk_cache.writes
	backend._execute_surface_batch(job)
	check(backend.poll()[0]==edited and backend.disk_cache.hits==hits and backend.disk_cache.writes==writes,"interactive input bypasses optional disk and dependency work")
	backend.active_input=false
	points[0].x+=1;job.points=points
	backend._execute_surface_batch(job);backend.poll()
	check(backend.disk_cache.writes==writes+1,"candidate coordinates participate in cache identity")
	var dependency:String=backend.native.geometry_cache_key(64,64,64,1).key
	var packet:=Codec.command(17,[points.size()]);packet.append_array(points.to_byte_array())
	var content:String=("surface-page-v1|"+dependency+"|"+backend.DiskCache.digest(packet).hex_encode()).sha256_text()
	var path:String=backend.disk_cache._name(Vector3i(64,64,64),content)
	var corrupted:=FileAccess.get_file_as_bytes(path);corrupted[corrupted.size()-1]^=1
	FileAccess.open(path,FileAccess.WRITE).store_buffer(corrupted)
	backend._execute_surface_batch(job)
	check(backend.poll()[0].points.size()==2 and backend.disk_cache.corrupt==1,"corrupt cached page is rebuilt rather than published")
	check(backend.disk_cache.total_bytes<16384,"surface-page cache remains compact and uses existing quota")
	check(not saved.is_empty(),"source fixture snapshot exists")
	backend.native=null
	print("FOREST_SURFACE_CACHE failures=",failures)
	quit(1 if failures else 0)
