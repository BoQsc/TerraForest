extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var commands:=0
var rows:Array[Dictionary]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func timed(core:RefCounted,packet:PackedByteArray,label:String)->PackedByteArray:
	var began:=Time.get_ticks_usec()
	var reply:PackedByteArray=core.execute(packet)
	commands+=1
	rows.append({"case":label,"ms":(Time.get_ticks_usec()-began)/1000.0,"ok":Codec.reply_ok(reply)})
	if not Codec.reply_ok(reply):check(false,"accepted native volume: "+label)
	return reply
func roundtrip(core:RefCounted,label:String)->void:
	var saved:PackedByteArray=core.execute(Codec.command(4,[3]))
	var restored:RefCounted=ClassDB.instantiate("TerrainCore")
	var packet:=Codec.command(5);packet.append_array(saved.slice(12))
	check(Codec.reply_ok(saved) and Codec.reply_ok(restored.execute(packet)) and restored.execute(Codec.command(4,[3]))==saved,label+": exact binary density/material/block roundtrip")
func mesh(core:RefCounted,origin:Vector3,label:String)->void:
	var packet:PackedByteArray=core.execute(Codec.command(1,[floori(origin.x/16)*16,floori(origin.z/16)*16,16,1]))
	var decoded:=Codec.decode_mesh(packet.slice(16)) if Codec.reply_ok(packet) else {"error":"native mesh rejected"}
	var valid:=not decoded.has("error")
	if valid:
		for vertex:Vector3 in decoded.arrays[Mesh.ARRAY_VERTEX]:valid=valid and vertex.is_finite()
		for normal:Vector3 in decoded.arrays[Mesh.ARRAY_NORMAL]:valid=valid and normal.is_finite()
	check(valid,label+": edited mesh has finite vertices/normals and valid packet")
func run()->void:
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	for generator:int in [3,23]:
		core.execute(Codec.command(6,[1703,generator]))
		for radius:float in [0.5,0.75,1,4,16,32,64]:
			for shape:int in [0,1]:
				var center:=Vector3(1024.25,96.25,1024.25)
				for add:bool in [true,false]:
					for material:int in [1,2,3]:
						var label:="g%d/r%.2f/s%d/add%s/m%d"%[generator,radius,shape,add,material]
						timed(core,Codec.brush(center,center+Vector3(7,2,5),radius,shape,add,material),label)
				mesh(core,center,"g%d/r%.2f/s%d"%[generator,radius,shape])
		for point:Vector3 in [Vector3(0,3,0),Vector3(1999,254,1999),Vector3(16,3,32),Vector3(32,254,16)]:
			for shape:int in [0,1]:
				for add:bool in [true,false]:timed(core,Codec.brush(point,point,4,shape,add,1),"world/page limits")
		var floor_sample:PackedByteArray=core.execute(Codec.point_command(Vector3(100,2,100)))
		check(floor_sample.decode_float(16)<0,"bedrock remains solid")
		roundtrip(core,"all sizes, shapes and boundary edits g%d"%generator)
	core.execute(Codec.command(6,[1703,5]))
	for count:int in range(6000):
		var center:=Vector3(768+(count%16)*2,64+(count/16%8),768+(count/128%16)*2)
		var packet:PackedByteArray
		match count%6:
			0:packet=Codec.brush(center,center,2.5,0,true,1)
			1:packet=Codec.brush(center,center+Vector3(1.5,-0.5,2),1.5,0,false,1)
			2:packet=Codec.brush(center,center+Vector3(0.25,0.25,0.25),2,1,true,2)
			3:packet=Codec.brush(center,center,1.5,1,false,1)
			4:packet=Codec.command(3,[int(center.x),int(center.y),int(center.z),3])
			5:packet=Codec.command(3,[int(center.x-2),int(center.y),int(center.z),0])
		timed(core,packet,"mixed_%d"%(count/1000))
		if (count+1)%1000==0:
			mesh(core,center,"mixed history %d"%(count+1))
			roundtrip(core,"mixed history %d"%(count+1))
	for material:int in [1,8,9,10]:
		for count:int in range(128):
			var point:=Vector3(900+count%16,120+count/16,900)
			timed(core,Codec.command(38,[int(point.x),int(point.y),int(point.z),material]),"paid stamp")
			var reply:=timed(core,Codec.brush(point,point,0.75,0,false,1),"re-mine stamp")
			var removed:=Codec.excavation_samples(reply)
			var total:=0
			for amount:int in removed:total+=amount
			if total!=1 or removed[material]!=1:check(false,"paid stamp yield stays exactly one")
	for width:float in [0.5,4,16]:
		for length:float in [1,32,128]:
			for material:int in [1,3,4]:
				var start:=Vector3(1200,100,1200)
				var finish:=start+Vector3(length,length*.25,0)
				var packet:=Codec.graded_bed(start,finish,width,8,16,material)
				packet.resize(48);packet.encode_float(44,16)
				timed(core,packet,"max grade/clearance/shoulder")
	roundtrip(core,"mixed history, paid material and roads")
	var before:PackedByteArray=core.execute(Codec.command(4,[3]))
	for packet:PackedByteArray in [Codec.brush(Vector3.ZERO,Vector3.ZERO,NAN,0,true,1),Codec.brush(Vector3.ZERO,Vector3.ZERO,65,0,true,1),Codec.command(38,[0,3,0,10]),Codec.command(3,[100,255,100,1]),Codec.graded_bed(Vector3(100,60,100),Vector3(101,62,100),4,4,8,4)]:
		check(not Codec.reply_ok(core.execute(packet)) and core.execute(Codec.command(4,[3]))==before,"invalid request is nonmutating")
	core.execute(Codec.command(6,[1703,5]))
	var rejected:=false
	var capacity_count:=0
	for count:int in range(160):
		var center:=Vector3(96+(count%12)*160,96,96+(count/12)*160)
		var reply:PackedByteArray=core.execute(Codec.brush(center,center,64,1,true,1))
		capacity_count+=1
		if not Codec.reply_ok(reply):rejected=true;break
	check(rejected,"finite resident page capacity rejects oversized history without crashing")
	var stats:PackedByteArray=core.execute(Codec.command(0))
	var before_capacity:PackedByteArray=core.execute(Codec.command(4,[3]))
	var outside:=Vector3(1960,96,1960)
	check(not Codec.reply_ok(core.execute(Codec.brush(outside,outside,64,1,true,1))) and core.execute(Codec.command(4,[3]))==before_capacity,"capacity rejection preserves exact existing terrain")
	check(Codec.reply_ok(core.execute(Codec.brush(Vector3(96,96,96),Vector3(96,96,96),0.75,0,false,1))),"existing-page mining continues after capacity rejection")
	FileAccess.open("res://reports/terrain_edit_volumes.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"commands":commands,"capacity_attempts":capacity_count,"capacity_pages":stats.decode_u32(20),"rows":rows,"scope":"Native synchronous volume/history validation, mesh packets and binary roundtrips. Two generators, every supported brush size boundary, 6000 mixed operations, 512 paid stamps/re-mines and road extrema. Capacity probe uses nonpaged core. Not GPU frames, physical input, multi-hour endurance or a complete combinatorial proof."},"  "))
	print("TERRAIN_EDIT_VOLUMES failures=",failures," commands=",commands);quit(1 if failures else 0)
