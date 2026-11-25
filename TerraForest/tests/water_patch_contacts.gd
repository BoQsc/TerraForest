# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks:=0
var failures:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	for descriptor in ["volumetric_water/volumetric_water","volumetric_terrain/terrain_core"]:
		GDExtensionManager.load_extension("res://addons/"+descriptor+".gdextension")
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,3]))),"isolated real terrain owner initialized")
	await check_wide_contact(core)
	var water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
	var origin:=Vector3i(200,400,200)
	var patch:=PackedByteArray();patch.resize(80);patch.fill(0)
	patch.encode_u32(0,0x50574654);patch.encode_u32(4,1);patch.encode_u32(12,1)
	for axis in 3:patch.encode_s32(16+axis*4,origin[axis]);patch.encode_s32(28+axis*4,1)
	patch.encode_u64(40,125000);patch.encode_u64(72,125000);patch.encode_u32(68,777)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(patch);patch.append_array(hash.finish())
	var token:Dictionary=water.water_patch_state()
	check(water.validate_water_patch(patch) and water.restore_water_patch(patch,token.revision,token.owner).ok,"valid one-cell water/vacancy baseline creates an unready owner")
	var request:Dictionary=water.next_request()
	check(not request.is_empty() and request.coordinate==origin/8,"normal terrain-work queue owns the missing region")
	if request.is_empty():finish();return
	var terrain_patch:RefCounted=ClassDB.instantiate("NativeWaterTerrainPatch")
	check(terrain_patch.configure(request.coordinate),"terrain occupancy request configured")
	var status:=0
	for step in 200:
		status=terrain_patch.sample_terrain(core,256,0,0)
		if status!=0:break
	check(status==1 and water.accept_patch(terrain_patch),"real density/contact sampling publishes restored region")
	check_wide_settlement(core,patch,false)
	check_wide_settlement(core,patch,false,true)
	var divided:RefCounted=ClassDB.instantiate("TerrainCore")
	divided.execute(Codec.command(6,[1703,3]))
	check(Codec.reply_ok(divided.execute(Codec.brush(Vector3(108,200,96),Vector3(108,200,132),2,0,true,1))),"finite-water test builds a terrain barrier across the brush")
	check_wide_settlement(divided,patch,true)
	token=water.water_patch_state()
	check(water.capture_water_patch(origin,Vector3i.ONE,token.revision,token.owner)==patch and water.statistics().water_ml==125000,"terrain contact hydration preserves every restored millilitre and vacancy")
	var batches:=0;var vertices:=0
	for step in 256:
		var batch:Dictionary=water.next_mesh_batch()
		if batch.is_empty():break
		vertices+=int(batch.get("vertices",0))
		if batch.get("complete",false):
			check(water.commit_mesh_batch(batch.batch),"normal water mesh batch commits")
			batches+=1
	check(batches>0 and vertices>0 and water.statistics().query_cache_bytes>0,"restored water builds visible geometry and the matching pick cache")
	var before:PackedByteArray=water.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))
	check_stencil_handoff(before)
	for step in 600:water.advance(2048,1.0/60.0)
	check(water.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))==before,"restoration never enables flow or changes static water after publication")
	water.settle_after_edit(AABB(Vector3(100.6,200.6,100.6),Vector3(32,1,32)))
	var first:Array=water.pending_edit_patches()
	check(first.size()==64,"a wet edit with over 64 waiting contacts exposes its first bounded batch")
	for coord:Vector3i in first:
		var part:RefCounted=ClassDB.instantiate("NativeWaterTerrainPatch")
		if not part.configure(coord):break
		var sampled:int=part.sample_terrain(core,2048,0,0)
		while sampled==0:sampled=part.sample_terrain(core,2048,0,0)
		if sampled!=1 or not water.accept_patch(part):break
	var remaining:Array=water.pending_edit_patches()
	check(remaining.size()==16 and remaining.all(func(coord):return not first.has(coord)),"after 64 accepted contacts only the 16 outstanding local receivers remain")
	check(water.statistics().water_ml==125000,"sampling consecutive local batches conserves the finite quantity")
	finish()

func check_stencil_handoff(saved:PackedByteArray)->void:
	var field:RefCounted=ClassDB.instantiate("TerrainCore")
	field.execute(Codec.command(6,[1703,3]))
	var prior:int=field.field_patch_state().revision
	var roof:=Vector3(101,232,101)
	var receipt:Dictionary=field.execute_edit_with_writes(Codec.brush(roof,roof,2,0,true,1))
	var rev:int=field.field_patch_state().revision
	var rect:=Rect2i(88,88,32,32)
	var reader:RefCounted=field.capture_edit_field(rect,rev,0)
	check(Codec.reply_ok(receipt.reply) and rev==prior+1 and reader!=null,"a real terrain write above water shares horizontal bounds with the wet owner")
	if reader==null:return
	var area:=AABB(Vector3(101,201,101),Vector3.ONE)
	var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
	var reference:=PackedByteArray()
	for ticket:int in [22,21]:
		var store:RefCounted=ClassDB.instantiate("NativeRegionalWater")
		check(store.restore_snapshot(saved),"restored donor has a committed contact profile")
		for attempt in 64:
			var batch:Dictionary=store.next_mesh_batch()
			if batch.is_empty():break
			if batch.complete:store.commit_mesh_batch(batch.batch)
		store.invalidate(area,false,21)
		var transaction:RefCounted=store.capture_local_edit(false,[area])
		check(transaction!=null,"pending wet replacement captures the old occupancy revision")
		if transaction==null:return
		check(transaction.set_field([{"core":reader,"bounds":rect}],AABB(Vector3(88,184,88),Vector3(32,48,32)),{},rev,0),"immutable contact field admitted")
		transaction.set_terrain_writes([receipt.writes],prior,ticket)
		transaction.prepare([])
		store.settle_after_edit(area)
		var result:Dictionary=store.accept_local_edit(transaction)
		check(result.get("unchanged_contact_bricks",-1)==(1 if ticket==21 else 0),"only the ticket that invalidated the donor may reuse its unaffected contact stencil")
		if result.has("batch"):store.commit_mesh_batch(result.batch)
		var encoded:PackedByteArray=store.capture_snapshot(catalog)
		if reference.is_empty():reference=encoded
		check(not encoded.is_empty() and encoded==reference and store.statistics().water_ml==125000,"reused and resampled contact produce identical persistent water and volume")

func check_wide_contact(core:RefCounted)->void:
	var lake:=preload("res://addons/volumetric_water/lake_world.gd").new()
	var coords:=[Vector3i(15,50,25),Vector3i(16,50,25),Vector3i(32,50,25)]
	var patches:Array=[]
	for coord:Vector3i in coords:
		var part:RefCounted=ClassDB.instantiate("NativeWaterTerrainPatch")
		check(part.configure(coord),"wide edit configures contact at "+str(coord))
		patches.append(part)
	var compact:Array=lake._group_edit_patches(coords.slice(0,2),patches.slice(0,2),Rect2i(60,100,8,4))
	check(compact.size()==1 and compact[0].patches.size()==2,"nearby patches crossing an aligned boundary share a snapshot")
	var groups:Array=lake._group_edit_patches(coords,patches,Rect2i(60,100,72,4))
	var token:Dictionary=core.field_patch_state()
	var build_epoch:PackedByteArray=core.execute(Codec.command(13))
	var job:={"groups":groups,"field":token.revision,"cancel":build_epoch.decode_u32(12),"ready":false,"ticket":1,"epoch":0}
	await run_contact_groups(lake,core,job)
	check(groups.size()==3 and job.ready,"72 m contact footprint completes on one authoritative revision")
	job.ready=false
	job.field+=1
	await run_contact_groups(lake,core,job)
	check(not job.ready,"stale wide contact cannot reach publication")
	var backend:=preload("res://addons/volumetric_terrain/terrain_backend.gd").new()
	backend.native=core
	var tiles:Array=[]
	for x in range(0,192,16):tiles.append({"key":Vector3i(x,96,16)})
	var view:Dictionary=backend._resident_edit_surface({"tiles":tiles,"ticket":1,"epoch":0,"build_epoch":job.cancel},token.revision)
	var shared:Array=lake._contact_groups(coords,patches,Rect2i(60,100,72,4),view.get("groups",[]))
	check(shared.size()==3 and shared.all(func(group):return group.has("core") and group.patches.size()==1),"wide water contacts reference all three terrain snapshots")
	for group:Dictionary in shared:
		var point:int=coords[shared.find(group)].x*4
		var packet:=Codec.command(43,[token.revision,job.cancel,point,200,100])
		check(group.core.execute(packet)==core.execute(packet),"shared terrain field reproduces the live water boundary packet")
		var fresh:RefCounted=ClassDB.instantiate("NativeWaterTerrainPatch")
		fresh.configure(coords[shared.find(group)])
		group.patches=[fresh]
	job.groups=shared
	job.field=token.revision
	job.ready=false
	await run_contact_groups(lake,null,job)
	check(job.ready,"production water sampling completes from the committed field readers without the live terrain owner")
	var mixed:Array=lake._contact_groups(coords,patches,Rect2i(60,100,72,4),view.groups.slice(0,2))
	check(mixed.size()==3 and not mixed.back().has("core") and mixed.back().patches==[patches[2]],"only uncovered water contacts request a separate snapshot")
	tiles.clear()
	for z in range(32,112,16):
		for x in range(32,112,16):tiles.append({"key":Vector3i(x,z,16)})
	var corner:Dictionary=backend._resident_edit_surface({"tiles":tiles,"ticket":2,"epoch":0,"build_epoch":job.cancel},token.revision)
	var covered:=0
	for item:Dictionary in tiles:
		var key:Vector3i=item.key
		var tile:=Rect2i(key.x,key.y,key.z,key.z)
		for group:Dictionary in corner.get("groups",[]):
			if Rect2i(group.bounds).encloses(tile):covered+=1
	check(corner.get("groups",[]).size()==4 and covered==tiles.size(),"all four sides of a region junction have exactly one shared field reader per tile")
	await process_frame
	lake.free()

func run_contact_groups(lake:Node,core:RefCounted,job:Dictionary)->void:
	var task:=WorkerThreadPool.add_group_task(lake._sample_contact_group.bind(core,job),job.groups.size())
	while not WorkerThreadPool.is_group_task_completed(task):await process_frame
	WorkerThreadPool.wait_for_group_task_completion(task)
	lake._finish_contact_groups(job)

func check_wide_settlement(core:RefCounted,source:PackedByteArray,barrier:bool,deep:bool=false)->void:
	var store:RefCounted=ClassDB.instantiate("NativeRegionalWater")
	var token:Dictionary=store.water_patch_state()
	check(store.restore_water_patch(source,token.revision,token.owner).ok,"wide settlement restores a single finite donor")
	var bounds:=AABB(Vector3(100.6,200.6,100.6),Vector3(32,52,24))
	if deep:bounds.position-=Vector3(8,4,8)
	store.settle_after_edit(bounds)
	check(store.pending_edit_patches().size()==1 and store.statistics().regions==1,"882-region edit starts at its sole resident donor")
	var requested:=0
	var furthest_x:=0
	var revision:int=core.field_patch_state().revision
	var done:=false
	for step in 128:
		for coord:Vector3i in store.pending_edit_patches():
			furthest_x=maxi(furthest_x,coord.x)
			var part:RefCounted=ClassDB.instantiate("NativeWaterTerrainPatch")
			part.configure(coord)
			var sampled:int=part.sample_terrain(core,2048,revision,0)
			while sampled==0:sampled=part.sample_terrain(core,2048,revision,0)
			if sampled!=1 or not store.accept_patch(part):
				check(false,"wide settlement samples reachable terrain")
				return
		var job:RefCounted=store.begin_equilibrium(1000,true)
		if job==null:continue
		job.prepare()
		var result:Dictionary=store.finish_equilibrium(job)
		if result.ok:
			if deep:check(result.get("wide_spans",0)>0 and result.wide_spans<result.wide_cells,"deep wide edit installs water from compressed open columns")
			done=true
			break
		if not result.get("pending",false):
			print("WIDE_SETTLEMENT_FAILURE ",result)
			break
		requested+=int(result.required_regions)
	var info:Dictionary=store.statistics()
	print("WIDE_SETTLEMENT barrier=",barrier," requested=",requested," resident=",info.regions," furthest_x=",furthest_x," water_ml=",info.water_ml)
	check(done and requested>0 and info.regions<882,"wide local solve discovers receivers and finishes without allocating the entire brush")
	check(info.water_ml==125000,"wide local publication preserves all finite water")
	if deep:
		var donor:Dictionary=store.cell_geometry(Vector3(100.25,200.25,100.25))
		var floor_a:Dictionary=store.cell_geometry(Vector3(100.25,196.25,100.25))
		var floor_b:Dictionary=store.cell_geometry(Vector3(104.25,196.25,104.25))
		check(is_equal_approx(donor.head,donor.bottom) and floor_a.head>floor_a.bottom and floor_b.head>floor_b.bottom and absf(floor_a.head-floor_b.head)<0.00001,"source drained into a level pool across multiple lower regions")
	if barrier:check(furthest_x<28,"a terrain wall keeps regions on the disconnected side out of settlement")

func finish()->void:
	print("WATER_PATCH_CONTACTS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
