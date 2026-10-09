# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,2]))
	var revision: int=core.execute(Codec.command(0)).decode_u32(12)
	var cottage=load("res://addons/structures/prefabs/brick_cottage.tres")
	var rows: Array[Dictionary]=[]
	var per_cottage_clearance:=0
	for count in [4,16,64,128]:
		var asset=ClassDB.instantiate("NativeBlockPrefab")
		var start:=Time.get_ticks_usec()
		check(asset.compose_frontage([cottage],count/2,8,3,1703),"compose %d authored cottages" % count)
		var compose_us:=Time.get_ticks_usec()-start
		var total: int=asset.clearance_sample_count()
		if count==4: per_cottage_clearance=total/4
		check(total==per_cottage_clearance*count and asset.get_cell_count()==cottage.get_cell_count()*count,"clearance and cells scale linearly at %d cottages" % count)
		var cursor:=0;var batches:=0;var sample_us:=0;var query_us:=0;var max_query_us:=0;var max_sample_us:=0;var max_bytes:=0
		while cursor<total:
			start=Time.get_ticks_usec()
			var points: PackedVector3Array=asset.clearance_samples(Vector3i(400,180,400),0,cursor,512)
			var elapsed:=Time.get_ticks_usec()-start;sample_us+=elapsed;max_sample_us=maxi(max_sample_us,elapsed)
			if points.is_empty() or points.size()>512: failures+=1;break
			var query:=Codec.command(29,[revision,points.size()]);query.append_array(points.to_byte_array())
			start=Time.get_ticks_usec()
			var reply: PackedByteArray=core.execute(query)
			elapsed=Time.get_ticks_usec()-start;query_us+=elapsed;max_query_us=maxi(max_query_us,elapsed)
			if not Codec.reply_ok(reply) or reply.size()!=20+points.size()*4: failures+=1;break
			max_bytes=maxi(max_bytes,query.size()+reply.size())
			cursor+=points.size();batches+=1
		check(cursor==total and max_bytes<=8224,"all clearance probes consumed with fixed-size packets at %d cottages" % count)
		var blocks=ClassDB.instantiate("NativeBlockWorld")
		start=Time.get_ticks_usec()
		var placed: bool=blocks.place_prefab(asset,Vector3i(400,180,400),0,false)
		var place_us:=Time.get_ticks_usec()-start
		check(placed,"place %d cottages in native block world" % count)
		start=Time.get_ticks_usec();var snapshot: PackedByteArray=blocks.capture_snapshot();var save_us:=Time.get_ticks_usec()-start
		var restored=ClassDB.instantiate("NativeBlockWorld")
		check(restored.restore_snapshot(snapshot) and restored.capture_snapshot()==snapshot,"exact snapshot roundtrip at %d cottages" % count)
		rows.append({"cottages":count,"cells":asset.get_cell_count(),"clearance_probes":total,"batches":batches,"compose_us":compose_us,"sample_us":sample_us,"max_sample_us":max_sample_us,"query_us":query_us,"max_query_us":max_query_us,"place_us":place_us,"snapshot_us":save_us,"snapshot_bytes":snapshot.size(),"max_packet_bytes":max_bytes})
		blocks.free();restored.free()
	var result:={"failures":failures,"scope":"CPU composition, native clearance sampling, native density queries, block insertion and storage only. No rendering, physics, worker queue latency, supported-site claim or 60 FPS claim.","rows":rows}
	var file:=FileAccess.open("res://reports/settlement_scale.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print(JSON.stringify(result));quit(1 if failures else 0)
