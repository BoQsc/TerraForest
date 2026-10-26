extends SceneTree
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func result_for(backend:RefCounted,kind:String)->Dictionary:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		for result:Dictionary in backend.poll():
			if result.kind==kind:return result
		await process_frame
	return {}
func run()->void:
	var folder:=ProjectSettings.globalize_path("user://edit_paging_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var store:RefCounted=ClassDB.instantiate("NativeTerrainRegionStore")
	check(store.open_store(folder,true),"isolated region store opens")
	var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,5]))
	var center:=Vector3(128,64,128)
	for index:int in range(12):
		var point:=center+Vector3(index%4*32,0,index/4*32)
		check(Codec.reply_ok(core.execute(Codec.brush(point,point,2,0,true,1))),"fixture page group %d"%index)
	var saved:PackedByteArray=core.execute(Codec.command(4,[3]))
	var reference:PackedByteArray=store.publish_capture(core.capture_storage_snapshot())
	for corrupt:bool in [false,true]:
		var backend:=Backend.new();backend.world_generator=5;backend.disk_cache.enabled=false
		check(backend.start(true)==OK and not (await result_for(backend,"startup")).is_empty(),"real ordered worker starts")
		check(backend.native.mount_storage_checkpoint(folder,reference,16),"checkpoint mounts with deliberately small page budget")
		var backups:Dictionary={}
		if corrupt:
			for name:String in DirAccess.get_files_at(folder):
				if name.ends_with(".tpack"):
					var path:=folder.path_join(name);var bytes:=FileAccess.get_file_as_bytes(path);backups[path]=bytes
					var changed:=bytes.duplicate();changed[0]^=1
					FileAccess.open(path,FileAccess.WRITE).store_buffer(changed)
		var packet:=Codec.brush(center,center,1 if corrupt else 40,0,false,1)
		check(backend.submit({"kind":"edit","command":packet,"tiles":[],"epoch":0,"ticket":1}),"failing edit submitted through worker")
		var result:=await result_for(backend,"edit")
		check(not result.is_empty() and not Codec.reply_ok(result.get("reply",PackedByteArray())),"worker reports rejection")
		var stats:Dictionary=backend.native.residency_stats()
		if corrupt:
			check(stats.storage_failures>0 and not result.get("recoverable",true) and not backend.write_allowed,"corrupt authoritative storage remains fatal, not a retryable capacity error")
			for path:String in backups:FileAccess.open(path,FileAccess.WRITE).store_buffer(backups[path])
		else:
			check(stats.failures>0 and stats.storage_failures==0 and result.get("recoverable",false) and backend.write_allowed,"pinned-page capacity rejection remains recoverable")
		check(backend.native.execute(Codec.command(4,[3]))==saved,"rejection preserves all authored density bytes")
		if not corrupt:
			packet=Codec.brush(center,center,0.75,0,false,1)
			check(backend.submit({"kind":"edit","command":packet,"tiles":[],"epoch":0,"ticket":2}),"small retry admitted")
			check(not (await result_for(backend,"edit_done")).is_empty() and backend.write_allowed,"small excavation publishes after oversized paged stroke")
		backend.stop();backend=null
	core=null;store.close();store=null
	for name:String in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	print("TERRAIN_EDIT_PAGED_RECOVERY failures=",failures);quit(1 if failures else 0)
