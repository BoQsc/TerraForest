extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var checks:=0
var durations:Array[float]=[]

func check(valid:bool,label:String)->void:
	checks+=1
	if not valid:failures+=1
	print("PASS " if valid else "FAIL ",label)

func mine(core:RefCounted,position:Vector3,normal:Vector3)->PackedByteArray:
	var began:=Time.get_ticks_usec()
	var reply:PackedByteArray=core.execute(Codec.brush(position,position-normal*.35,.65,Codec.CONTACT_MINING_SHAPE,false,1))
	durations.append((Time.get_ticks_usec()-began)/1000.0)
	return reply

func removed(reply:PackedByteArray)->int:
	var total:=0
	for count:int in Codec.excavation_samples(reply):total+=count
	return total

func restore(core:RefCounted,bytes:PackedByteArray)->bool:
	var packet:=Codec.command(5);packet.append_array(bytes.slice(12))
	return Codec.reply_ok(core.execute(packet))

func pick(core:RefCounted,origin:Vector3,endpoint:Vector3)->Dictionary:
	return Codec.decode_density_ray(core.execute(Codec.density_ray_command(origin,endpoint,64,core.execute(Codec.command(13)).decode_u32(12),true)))

func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	var samples:=0
	for offset:Vector3 in [Vector3.ZERO,Vector3.ONE*.5,Vector3(.125,.875,.375)]:
		core.execute(Codec.command(6,[1703,5]))
		var center:=Vector3(136,64,136)+offset
		core.execute(Codec.brush(center,center,3.5,0,true,1))
		var baseline:PackedByteArray=core.execute(Codec.command(4,[3]))
		var mesh_reply:PackedByteArray=core.execute(Codec.command(1,[128,128,16,1]))
		var decoded:=Codec.decode_mesh(mesh_reply.slice(16))
		if decoded.has("error"):check(false,"fixture mesh decodes");continue
		var vertices:PackedVector3Array=decoded.arrays[Mesh.ARRAY_VERTEX]
		var normals:PackedVector3Array=decoded.arrays[Mesh.ARRAY_NORMAL]
		var indices:PackedInt32Array=decoded.arrays[Mesh.ARRAY_INDEX]
		for triangle in range(0,indices.size()-2,maxi(3,(indices.size()/90)*3)):
			restore(core,baseline)
			var position:Vector3=(vertices[indices[triangle]]+vertices[indices[triangle+1]]+vertices[indices[triangle+2]])/3.0
			var normal:Vector3=(normals[indices[triangle]]+normals[indices[triangle+1]]+normals[indices[triangle+2]]).normalized()
			var reply:=mine(core,position,normal)
			check(Codec.reply_ok(reply) and reply.decode_u32(16)>0 and removed(reply)>0,"rendered surface contact removes solid sample %d"%samples)
			samples+=1
		for axis:Vector3 in [Vector3.UP,Vector3.DOWN,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK,Vector3(1,1,1).normalized()]:
			restore(core,baseline)
			var origin:=center+axis*6.0
			var endpoint:=center-axis*6.0
			var strikes:=0
			for step in 24:
				var hit:=pick(core,origin,endpoint)
				if hit.status!="hit":break
				var reply:=mine(core,hit.position,hit.normal)
				if not Codec.reply_ok(reply) or removed(reply)==0:check(false,"repeated mining progresses %s step %d"%[axis,step]);break
				strikes+=1
			check(strikes>=4,"successive same-aim strikes cross sphere %s"%axis)
	core.execute(Codec.command(6,[1703,5]))
	for material:int in [1,8,9,10]:
		var center:=Vector3(128,64,128)
		core.execute(Codec.command(38,[128,64,128,material]))
		var hit:=pick(core,center+Vector3.UP*3,center-Vector3.UP)
		var reply:=mine(core,hit.position,hit.normal)
		check(removed(reply)==1 and Codec.excavation_samples(reply)[material]==1,"paid material yields exactly one unit %d"%material)
		check(removed(mine(core,hit.position,hit.normal))==0,"old contact does not duplicate paid yield %d"%material)
	var unchanged:PackedByteArray=core.execute(Codec.command(4,[3]))
	for packet:PackedByteArray in [Codec.brush(Vector3(128,64,128),Vector3(128,64,128),.65,3,true,1),Codec.brush(Vector3(128,64,128),Vector3(128,66,128),.65,3,false,1),Codec.brush(Vector3(128,64,128),Vector3(128,64,128),2,3,false,1),Codec.brush(Vector3(NAN,64,128),Vector3(128,64,128),.65,3,false,1)]:
		check(not Codec.reply_ok(core.execute(packet)) and core.execute(Codec.command(4,[3]))==unchanged,"invalid contact request is nonmutating")
	for position:Vector3 in [Vector3(128,128,128),Vector3(128,3,128),Vector3(-4,64,128),Vector3(2004,64,128)]:
		var reply:=mine(core,position,Vector3.UP)
		check(Codec.reply_ok(reply) and reply.decode_u32(16)==0 and core.execute(Codec.command(4,[3]))==unchanged,"empty/protected/outside contact cannot mine %s"%position)
	var store:RefCounted=ClassDB.instantiate("NativeTerrainRegionStore")
	var folder:="user://contact_mining_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	check(store.open_store(ProjectSettings.globalize_path(folder),true),"isolated paged store opens")
	for index in 20:
		var center:=Vector3(128+index*32,64,128)
		core.execute(Codec.brush(center,center,2.5,0,true,1))
	var reference:PackedByteArray=store.publish_capture(core.capture_storage_snapshot())
	check(core.mount_storage_checkpoint(ProjectSettings.globalize_path(folder),reference,16),"contact fixture mounts with evicted pages")
	var hit:=pick(core,Vector3(128.5,70,128.5),Vector3(128.5,60,128.5))
	check(removed(mine(core,hit.position,hit.normal))>0 and core.residency_stats().resident_pages<=16,"contact mining hydrates only bounded resident pages")
	var saved:PackedByteArray=core.execute(Codec.command(4,[3]))
	check(restore(core,saved) and core.execute(Codec.command(4,[3]))==saved,"contact excavation preserves exact save roundtrip")
	store.close()
	durations.sort()
	var report_folder:=ProjectSettings.globalize_path("res://reports")
	DirAccess.make_dir_recursive_absolute(report_folder)
	FileAccess.open(report_folder.path_join("terrain_contact_mining.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"surface_contacts":samples,"operations":durations.size(),"p95_ms":durations[int(durations.size()*.95)],"max_ms":durations.back(),"scope":"Finite native contact, repeated excavation, paid-resource, boundary, paged-residency and exact binary roundtrip checks."},"  "))
	print("CONTACT_MINING_TIMING count=",durations.size()," p95_ms=",durations[int(durations.size()*.95)]," max_ms=",durations.back())
	print("TERRAIN_CONTACT_MINING checks=",checks," failures=",failures);quit(1 if failures else 0)
