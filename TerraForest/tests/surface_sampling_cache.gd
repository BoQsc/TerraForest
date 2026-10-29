extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var checks:=0
var output:="res://reports/surface_sampling_cache"
var comparison:=""
var records:Array=[]
var expected:Array=[]
var core:RefCounted

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func measure(packet:PackedByteArray,label:String)->PackedByteArray:
	var first:PackedByteArray=core.execute(packet)
	check(Codec.reply_ok(first),label+" accepts bounded support batch")
	var began:=Time.get_ticks_usec()
	var stable:=true
	for repeat in 16:stable=core.execute(packet)==first and stable
	var elapsed:=Time.get_ticks_usec()-began
	check(stable,label+" repeated queries are byte-identical")
	if not expected.is_empty():
		check(records.size()<expected.size() and expected[records.size()].label==label and expected[records.size()].reply==first.hex_encode(),label+" matches pre-optimization bytes")
	records.append({"label":label,"reply":first.hex_encode(),"microseconds":elapsed,"batches":16,"points":packet.decode_u32(4)})
	return first

func _initialize()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile-dir="):output=argument.trim_prefix("--profile-dir=")
		if argument.begins_with("--compare="):comparison=argument.trim_prefix("--compare=")
	if not comparison.is_empty():
		var saved=JSON.parse_string(FileAccess.get_file_as_string(comparison))
		if saved is Dictionary:expected=saved.get("records",[])
		check(not expected.is_empty(),"reference results load")
	core=ClassDB.instantiate("TerrainCore")
	for profile in [1,17,21,31]:
		for seed_value in [42,1703]:
			check(Codec.reply_ok(core.execute(Codec.command(6,[seed_value,profile]))),"terrain fixture initializes")
			for origin in [Vector2(2,2),Vector2(384,248),Vector2(784,1304),Vector2(992,992),Vector2(1968,1968)]:
				var points:=PackedVector3Array()
				for index in 64:points.append(Vector3(origin.x+(index%8)*3.99+.001,0,origin.y+int(index/8)*3.99+.999))
				var packet:=Codec.command(17,[points.size()]);packet.append_array(points.to_byte_array())
				var label:="%d/%d/%s"%[profile,seed_value,str(origin)]
				var initial:=measure(packet,label+" natural")
				var point:=Vector3(initial.decode_float(16),initial.decode_float(20),initial.decode_float(24))
				check(Codec.reply_ok(core.execute(Codec.brush(point,point,1.5,0,false,1))),label+" mining accepted")
				measure(packet,label+" mined")
				check(Codec.reply_ok(core.execute(Codec.brush(point+Vector3.UP*.3,point+Vector3.UP*.3,1.5,0,true,3))),label+" material fill accepted")
				measure(packet,label+" filled")
				var road_point:=Vector3(initial.decode_float(232),initial.decode_float(236),initial.decode_float(240))
				check(Codec.reply_ok(core.execute(Codec.road_bed(road_point,road_point+Vector3(8,0,0),2,2,2))),label+" asphalt accepted")
				measure(packet,label+" paved")
	if not expected.is_empty():check(records.size()==expected.size(),"all reference batches compared")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records},"  "))
	print("SURFACE_SAMPLING_CACHE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
