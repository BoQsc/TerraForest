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
	for step in 600:water.advance(2048,1.0/60.0)
	check(water.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))==before,"restoration never enables flow or changes static water after publication")
	finish()
func finish()->void:
	print("WATER_PATCH_CONTACTS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
