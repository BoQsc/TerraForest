extends SceneTree
var checks:=0
var failures:=0
func _initialize()->void:
	if not ClassDB.class_exists("NativeBlockWorld"):GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var world:Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(world)
	var asset=ClassDB.instantiate("NativeBlockPrefab")
	for material in 4:
		for rotation in 4:
			var word:int=128+material*32+rotation*8
			check(world.set_cells(PackedInt32Array([0,0,0,word])),"upper plate accepts material/rotation "+str(word))
			var samples:PackedByteArray=world.sample_solid(PackedVector3Array([Vector3(.5,.74,.5),Vector3(.5,.76,.5),Vector3(.5,.99,.5),Vector3(.5,1.01,.5)]))
			check(samples==PackedByteArray([0,1,1,0]),"upper quarter is authoritative solid, not a full cell")
			var hit:Dictionary=world.raycast_cells(Vector3(.5,2,.5),Vector3(.5,-1,.5))
			check(hit.get("position",Vector3.INF).distance_to(Vector3(.5,1,.5))<.001,"plate hit surface meets integer block grid")
			check(asset.configure(PackedInt32Array([0,0,0,word])) and asset.get_material_counts()[material]==1,"prefab costs preserve the ordinary material")
	var preview:Mesh=world.preview_mesh(8,0)
	check(preview!=null and preview.get_aabb().position.is_equal_approx(Vector3(0,.75,0)) and preview.get_aabb().size.is_equal_approx(Vector3(1,.25,1)),"rendered plate is one metre square and one quarter metre thick")
	world.flush_bakes()
	check(world.set_cells(PackedInt32Array([0,1,0,1])) and world.get_cell(Vector3i(0,1,0))==1,"ordinary block stacks flush above the plate")
	var snapshot:PackedByteArray=world.capture_snapshot()
	var restored:Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(restored)
	check(restored.restore_snapshot(snapshot) and restored.capture_snapshot()==snapshot,"binary world roundtrip retains plate shape and neighboring block")
	var region:PackedByteArray=world.capture_region(Vector3i.ZERO)
	check(restored.restore_region(region,restored.capture_region(Vector3i.ZERO)) and restored.get_cell(Vector3i.ZERO)==248,"region archive retains plate encoding")
	world.configure_history(1024*1024,16)
	check(world.set_cells(PackedInt32Array([0,0,0,0])) and world.get_cell(Vector3i(0,1,0))==1,"removing one plate leaves the neighboring construction intact")
	check(world.undo() and world.get_cell(Vector3i.ZERO)==248 and world.get_cell(Vector3i(0,1,0))==1,"undo restores exactly the removed plate")
	check(world.redo() and world.get_cell(Vector3i.ZERO)==0 and world.get_cell(Vector3i(0,1,0))==1,"redo removes exactly that plate again")
	for invalid in [129,255,256,-1,8]:check(not world.set_cells(PackedInt32Array([0,0,0,invalid])),"unknown shape words still reject "+str(invalid))
	var roads:Array=[{"start":Vector3(100,40,100),"finish":Vector3(128,40,100),"half_width":3.0},{"start":Vector3(128,40,100),"finish":Vector3(142,41,100),"half_width":3.0},{"start":Vector3(99.5,40,100),"finish":Vector3(100.5,40,100),"half_width":3.0}]
	var plan:Dictionary=asset.plan_paving(roads)
	check(plan.get("ok",false) and plan.tiles>0 and plan.terrain_ramps==1,"native planner produces plates and preserves smooth terrain ramps")
	check(plan==asset.plan_paving(roads),"native paving is deterministic")
	var corridor:=Rect2(Vector2(115,90),Vector2(5,10))
	var access_plan:Dictionary=asset.plan_paving(roads,[corridor])
	var open:bool=access_plan.get("ok",false) and access_plan.tiles<plan.tiles and access_plan.tiles>0
	for offset in range(0,access_plan.records.size(),4):
		open=open and not corridor.intersects(Rect2(Vector2(access_plan.records[offset],access_plan.records[offset+2]),Vector2.ONE))
	for bed:Dictionary in access_plan.beds:
		var low:Vector3=bed.start.min(bed.finish)-Vector3(bed.half_width,0,bed.half_width)
		var high:Vector3=bed.start.max(bed.finish)+Vector3(bed.half_width,0,bed.half_width)
		open=open and not corridor.intersects(Rect2(Vector2(low.x,low.z),Vector2(high.x-low.x,high.z-low.z)))
	check(open,"driveway cutout excludes both sidewalk cells and their terrain cuts")
	check(not asset.plan_paving(roads,[Rect2(Vector2(NAN,0),Vector2.ONE)]).get("ok",false) and not asset.plan_paving(roads,[false]).get("ok",false),"invalid access corridors reject atomically")
	var normalized_roads:=roads.duplicate(true)
	for road:Dictionary in normalized_roads:road["grid_normalized"]=true
	var normalized:Dictionary=asset.plan_paving(normalized_roads)
	check(normalized.records==plan.records and normalized.beds.size()==plan.beds.size(),"grid preference preserves every trusted destructible plate")
	var shallow_beds:=true
	for index in plan.beds.size():
		shallow_beds=shallow_beds and absf(normalized.beds[index].start.y-plan.beds[index].start.y-.07)<.00001 and absf(normalized.beds[index].finish.y-plan.beds[index].finish.y-.07)<.00001
	check(shallow_beds,"grid preference raises shallow plate-bed cuts without moving construction")
	var aligned:=true;var unique:Dictionary={}
	for offset in range(0,plan.records.size(),4):
		var cell:=Vector3i(plan.records[offset],plan.records[offset+1],plan.records[offset+2])
		aligned=aligned and cell.y==39 and cell.x<128 and plan.records[offset+3]==192 and not unique.has(cell)
		aligned=aligned and absf(cell.z+.5-100)>=3 and Vector2(cell.x+.5-100,cell.z+.5-100).length()>=6.5
		unique[cell]=true
	check(aligned,"tiles are individually keyed, road-clear, junction-clear and do not stair-step ramps")
	check(asset.configure(plan.records) and restored.place_prefab(asset,Vector3i.ZERO,0,false),"normal native prefab publication creates destructible paving cells")
	check(not restored.place_prefab(asset,Vector3i.ZERO,0,false),"paving publication cannot overwrite existing construction")
	check(not asset.plan_paving([{"start":Vector3.INF,"finish":Vector3.ZERO}]).get("ok",false),"invalid geometry cannot generate paving")
	check(not asset.plan_paving([]).get("ok",false),"empty plans fail explicitly")
	world.free();restored.free();await process_frame;await process_frame
	var output:="res://reports/paving_blocks.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--paving-output="):output=argument.trim_prefix("--paving-output=")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var report:=FileAccess.open(output,FileAccess.WRITE)
	if report==null:failures+=1;print("FAIL paving report could not be written")
	else:report.store_string(JSON.stringify({"checks":checks,"failures":failures}));report.close()
	print("PAVING_BLOCKS checks=",checks," failures=",failures);quit(1 if failures else 0)
