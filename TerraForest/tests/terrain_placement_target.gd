extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var checks:=0
func check(valid:bool,label:String)->bool:
	checks+=1
	if not valid:failures+=1
	print("PASS " if valid else "FAIL ",label)
	return valid
func info(core:RefCounted)->int:return core.execute(Codec.command(0)).decode_u32(12)
func density(core:RefCounted,point:Vector3)->float:
	var packet:=Codec.point_command(point);packet.encode_u32(0,26)
	return core.execute(packet).decode_float(16)
func pick(core:RefCounted,from:Vector3,to:Vector3)->Dictionary:
	return Codec.decode_density_ray(core.execute(Codec.density_ray_command(from,to,64,core.execute(Codec.command(13)).decode_u32(12),true)))
func resolve(core:RefCounted,hit:Dictionary)->Dictionary:
	return Codec.decode_terrain_target(core.execute(Codec.terrain_target_command(hit.position,hit.normal,info(core),core.execute(Codec.command(13)).decode_u32(12))))
func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	var planner:RefCounted=ClassDB.instantiate("NativeTerrainPlanner")
	var covered:=0;var buried_before:=0;var occupied_before:=0
	for material:int in [10,1,8,9]:
		core.execute(Codec.command(6,[1703,5]))
		var cell:=Vector3i(800,120,1310)
		core.execute(Codec.command(38,[cell.x,cell.y,cell.z,material]))
		for step in 4:
			var hit:=pick(core,Vector3(cell)+Vector3(0,3,0),Vector3(cell)-Vector3.UP)
			if not check(hit.get("status")=="hit","native placed material supplies a surface %d/%d"%[material,step]):continue
			var selected:=resolve(core,hit)
			if not check(selected.get("status")=="hit","native target resolves above placed material"):continue
			var next:Vector3i=selected.cell
			check(next.y==cell.y+1 and density(core,Vector3(next))>=0 and (Vector3(next)-hit.position).dot(hit.normal)>=.039,"next target is the adjacent empty sample without skipping a layer")
			var revision:=info(core)
			var placed:PackedByteArray=core.execute(Codec.command(38,[next.x,next.y,next.z,material]))
			check(Codec.reply_ok(placed) and info(core)>revision,"consecutive paid stamp changes terrain instead of refunding a filled sample")
			cell=next
		for offset_x:float in [-.45,-.25,0,.25,.45]:
			for offset_z:float in [-.45,-.25,0,.25,.45]:
				var hit:=pick(core,Vector3(cell)+Vector3(offset_x,2,offset_z),Vector3(cell)+Vector3(offset_x,-1,offset_z))
				if hit.get("status")!="hit":continue
				var old:Vector3=(hit.position+hit.normal*.25).round()
				if (old-hit.position).dot(hit.normal)<.35:buried_before+=1
				if density(core,old)<0:occupied_before+=1
				var chosen:=resolve(core,hit)
				if chosen.get("status")!="hit" or density(core,Vector3(chosen.cell))<0 or (Vector3(chosen.cell)-hit.position).dot(hit.normal)<.039:failures+=1
				covered+=1
	var revision:=info(core);var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
	var low_surface:={"position":Vector3(800,124.24,1310),"normal":Vector3.UP}
	var old_target:Vector3=(low_surface.position+low_surface.normal*.25).round()
	check(density(core,old_target)<0,"low meshed crown reproduces the old occupied-sample rounding")
	var corrected:=resolve(core,low_surface)
	check(corrected.get("status")=="hit" and corrected.cell.y==125 and density(core,Vector3(corrected.cell))>=0,"low crown resolves to the next empty sample instead of a no-op")
	check(corrected.empty.size()==16,"125 empty samples fit in a fixed sixteen-byte mask")
	var cache_checks:=0;var cache_failures:=0
	for offset_x:float in [-.8,-.4,0,.4,.8]:
		for offset_z:float in [-.8,-.4,0,.4,.8]:
			for normal:Vector3 in [Vector3.UP,Vector3(.3,.9,.2).normalized(),Vector3(-.3,.9,-.2).normalized()]:
				var point:Vector3=low_surface.position+Vector3(offset_x,0,offset_z)
				var direct:=resolve(core,{"position":point,"normal":normal})
				var local:Dictionary=planner.placement_target(point,normal,corrected.origin,corrected.empty)
				cache_checks+=1
				if local.status!=direct.status or local.get("cell")!=direct.get("cell"):cache_failures+=1
	check(cache_checks==75 and cache_failures==0,"moving point and normal reuse the mask with exact authoritative selector parity")
	check(planner.placement_target(low_surface.position+Vector3(2,0,0),Vector3.UP,corrected.origin,corrected.empty).status=="outside","moving outside full mask coverage requires a fresh query")
	check(planner.placement_target(low_surface.position,Vector3.ZERO,corrected.origin,corrected.empty).status=="outside","cached selection rejects invalid surface normals")
	check(planner.placement_target(low_surface.position,Vector3.UP,corrected.origin,PackedByteArray([1])).status=="outside","truncated masks never authorize a placement")
	var occupied:=PackedByteArray();occupied.resize(16)
	check(planner.placement_target(low_surface.position,Vector3.UP,corrected.origin,occupied).status=="miss","fully occupied masks cannot invent an empty sample")
	check(covered>=80 and buried_before>0,"shoulder sweep reproduces embedded old markers and resolves exposed empty targets")
	check(Codec.decode_terrain_target(core.execute(Codec.terrain_target_command(Vector3(800,124,1310),Vector3.UP,revision-1,epoch))).status=="stale","stale field revision cannot authorize a target")
	check(not Codec.reply_ok(core.execute(Codec.terrain_target_command(Vector3(800,124,1310),Vector3.ZERO,revision,epoch))),"invalid normal is rejected without a target")
	check(info(core)==revision,"placement queries never modify authoritative terrain")
	var evidence:="res://reports"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--target-evidence="):evidence=argument.trim_prefix("--target-evidence=")
	DirAccess.make_dir_recursive_absolute(evidence)
	var report:=FileAccess.open(evidence.path_join("terrain_placement_target.json"),FileAccess.WRITE)
	if report:report.store_string(JSON.stringify({"checks":checks,"failures":failures,"shoulders":covered,"old_embedded":buried_before,"old_occupied":occupied_before}))
	else:check(false,"native target report is writable")
	print("TERRAIN_PLACEMENT_TARGET checks=",checks," failures=",failures," old_embedded=",buried_before," old_occupied=",occupied_before)
	quit(1 if failures else 0)
