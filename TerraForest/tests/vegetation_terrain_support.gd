extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func probe(core:RefCounted,command:int,revision:int,points:PackedVector3Array)->PackedByteArray:
	var packet:=Codec.command(command,[revision,points.size()]);packet.append_array(points.to_byte_array())
	return core.execute(packet)
func fused_probe()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,5]))
	core.execute(Codec.road_bed(Vector3(100,64,100),Vector3(116,64,100),4,4,8))
	core.execute(Codec.command(3,[108,66,100,1]))
	var revision:int=core.execute(Codec.command(0)).decode_u32(12)
	var saved:PackedByteArray=core.execute(Codec.command(4))
	var points:=PackedVector3Array()
	for index in 512:points.append(Vector3(108.25,63.1+float(index%8)*.5,100.25))
	var fused:=probe(core,40,revision,points)
	var density:=probe(core,31,revision,points);var blocks:=probe(core,33,revision,points)
	var exact:=Codec.reply_ok(fused) and fused.size()==20+512*8
	if not exact:check(false,"fused vegetation probe reply is complete");return
	for index in 512:
		var expected:=density.decode_float(20+index*4)
		if blocks.decode_float(20+index*4)>0:expected=-maxf(absf(expected),.001)
		exact=exact and is_equal_approx(fused.decode_float(20+index*4),expected)
	check(exact,"fused 512-point vegetation probe matches density and voxel occupancy")
	check(fused.decode_float(20+512*4)==1 and fused.decode_float(20+512*4+7*4)==0,"fused paving channel excludes solid asphalt, not air above it")
	check(not Codec.reply_ok(probe(core,40,revision+1,points)) and not Codec.reply_ok(probe(core,40,revision,PackedVector3Array([Vector3(-1,64,0)]))),"fused probes reject stale and out-of-world samples")
	check(core.execute(Codec.command(4))==saved,"vegetation probes never mutate terrain storage")
func _initialize()->void:
	fused_probe()
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	var support=ClassDB.instantiate("NativeVegetationSupport")
	var ids:=PackedInt64Array([1,2,3,4,5,6])
	var probe:={"ids":ids,"offsets":PackedInt32Array([0,2,4,6,8,10,12])}
	var before:={"density":PackedFloat32Array([-.08,.08,-.08,.08,-.08,.08,.1,.2,-.08,.08,-.08,.08]),"blocks":PackedFloat32Array([0,0,0,0,0,0,0,0,0,0,0,0])}
	var after:={"density":PackedFloat32Array([.2,.3,-.2,-.1,-.08,.08,.1,.2,-.08,.08,-.01,.01]),"blocks":PackedFloat32Array([0,0,0,0,0,0,0,0,0,1,0,0])}
	check(support.lost_roots(probe,before,after)=={"ok":true,"ids":PackedInt64Array([1,2,5]),"destroyed":PackedInt64Array([1,2,5])},"only excavated, buried or voxel-occupied roots are removed")
	var paving:Dictionary=before.duplicate(true);paving.paved=PackedFloat32Array([1,0,0,0,0,0,0,0,0,0,0,0])
	check(support.lost_roots(probe,before,paving).ids==PackedInt64Array([1]) and support.lost_roots(probe,before,paving).destroyed.is_empty(),"asphalt-only exclusion remains reversible rather than pretending terrain was excavated")
	check(support.lost_roots(probe,before,before).ids.is_empty(),"no-op and unrelated edits retain every root, including preexisting unsupported objects")
	check(not support.lost_roots({"ids":PackedInt64Array([1]),"offsets":probe.offsets},before,after).ok,"malformed sample count fails closed")
	var invalid:Dictionary=after.duplicate(true);invalid.density[0]=NAN
	check(not support.lost_roots(probe,before,invalid).ok,"nonfinite samples cannot authorize removal")
	var poses:Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(32.05,10,32)),Transform3D(Basis.IDENTITY,Vector3(32.25,10,32))]
	var tree:Dictionary=support.tree_probes(PackedInt64Array([1,2]),poses,AABB(Vector3(32,9,31),Vector3(.1,2,2)))
	check(tree.ids==PackedInt64Array([1]) and tree.points[0].is_equal_approx(Vector3(32.05,10.12,32)),"centimetre-scale selection uses each tree root, not its whole owner or canopy")
	check(support.filter_trees(PackedInt64Array([1,2]),poses,PackedInt64Array([1])).transforms==[poses[1]],"tree filtering preserves exact surviving transforms")
	var rows:Array=[]
	for species in 9:rows.append({"ids":PackedInt64Array(),"transforms":PackedFloat32Array()})
	rows[2]={"ids":PackedInt64Array([1,2,4294967296]),"transforms":PackedFloat32Array([1,0,0,32.05,0,1,0,10,0,0,1,32,1,0,0,32.25,0,1,0,10,0,0,1,32,1,0,0,32.07,0,1,0,10.05,0,0,1,32])}
	var grass:Dictionary=support.ground_probes(rows,AABB(Vector3(32,9,31),Vector3(.1,2,2)))
	check(grass.ids==PackedInt64Array([1,4294967296]) and is_equal_approx(grass.points[0].y,grass.points[grass.offsets[1]].y),"natural and player-planted clumps share exact surface anchoring")
	var elevated:Dictionary=support.tree_probes(PackedInt64Array([1,2]),poses,AABB(Vector3(32,14,31),Vector3(.1,1,2)))
	check(elevated.ids==PackedInt64Array([1]) and elevated.points.has(Vector3(32.05,15,32)),"elevated deposits check the trunk without using its canopy as a clearing box")
	var kept:Array=support.filter_ground(rows,PackedInt64Array([1,4294967296]))
	check(kept[2].ids==PackedInt64Array([2]) and kept[2].transforms==rows[2].transforms.slice(12,24),"sub-owner deletion preserves the neighbouring clump byte for byte")
	var removed:Array=support.filter_ground(rows,PackedInt64Array([1,4294967296]),true)
	check(removed[2].ids==grass.ids,"render deletion receives only selected identities")
	var state=ClassDB.instantiate("NativeGroundCoverState");state.bind_world(1703,1)
	var authored:int=state.add(2,poses[0]);var snapshot:PackedByteArray=state.capture_storage_snapshot()
	check(not state.remove_roots(PackedInt64Array([1,-1])) and state.capture_storage_snapshot()==snapshot,"invalid removal batch leaves persistence unchanged")
	check(state.remove_roots(PackedInt64Array([1,authored])) and state.contains(1) and state.profile().placed==0,"natural removals and authored destruction persist without inventory rewards")
	var clone=ClassDB.instantiate("NativeGroundCoverState")
	check(clone.restore_storage_snapshot(state.capture_storage_snapshot()) and clone.contains(1) and clone.profile().placed==0,"fresh state restores exact removals")
	var harvest=ClassDB.instantiate("NativeHarvestState")
	check(harvest.remove_roots(PackedInt64Array([1,2])) and harvest.mask(PackedInt64Array([1,2,3]))==PackedByteArray([1,1,0]),"tree removal uses existing durable identity storage")
	print("VEGETATION_TERRAIN_SUPPORT failures=",failures);quit(1 if failures else 0)
