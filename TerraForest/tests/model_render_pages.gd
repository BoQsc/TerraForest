# SPDX-License-Identifier: 0BSD
extends SceneTree

const ASSET:="test/model_render_pages"
const REGION:=Vector3i(-1,-1,0)
var checks:=0
var failures:=0
var output:="res://reports/model_render_pages"
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func packed(pose:Transform3D)->PackedFloat32Array:
	return PackedFloat32Array([pose.basis.x.x,pose.basis.y.x,pose.basis.z.x,pose.origin.x,pose.basis.x.y,pose.basis.y.y,pose.basis.z.y,pose.origin.y,pose.basis.x.z,pose.basis.y.z,pose.basis.z.z,pose.origin.z])
func digest(bytes:PackedByteArray)->PackedByteArray:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish()
func resigned(bytes:PackedByteArray)->PackedByteArray:
	var payload:=bytes.slice(24,bytes.size()-64)
	var result:=bytes.slice(0,24);result.append_array(payload);result.append_array(digest(payload));result.append_array(digest(result));return result
func decoded(bytes:PackedByteArray,region:Vector3i=REGION)->RefCounted:
	var result:RefCounted=ClassDB.instantiate("NativeModelRenderPage")
	if not result.load_packet(bytes,bytes.slice(bytes.size()-32),ASSET,region):return null
	return result
func wait_for(archive:RefCounted,ticket:int)->Dictionary:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		var result:Dictionary=archive.take_model_render_region_read(ticket)
		if not result.is_empty():return result
		await process_frame
	return {}
func wait_empty(archive:RefCounted)->bool:
	var deadline:=Time.get_ticks_msec()+10000
	while archive.region_read_stats().outstanding>0 and Time.get_ticks_msec()<deadline:await process_frame
	return archive.region_read_stats().outstanding==0
func prototype()->ArrayMesh:
	var mesh:=ArrayMesh.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-1,0,-1),Vector3(1,0,-1),Vector3(1,1,1),Vector3(-1,1,1)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{0.4:PackedInt32Array([0,1,2])})
	var material:=StandardMaterial3D.new();material.albedo_color=Color.CORNFLOWER_BLUE;mesh.surface_set_material(0,material)
	return mesh
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--view-output="):output=argument.trim_prefix("--view-output=")
		if argument.begins_with("--profile-dir="):output=argument.trim_prefix("--profile-dir=")
	DirAccess.make_dir_recursive_absolute(output)
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var counter:RefCounted=ClassDB.instantiate("NativeModelRenderPage")
	check(counter.live_pages()==0,"no render payload exists before use")
	var source:Node3D=ClassDB.instantiate("NativeStaticBatch")
	var mesh:=prototype()
	check(source.configure_collision_only() and source.configure_asset(ASSET,mesh),"canonical fixture configures without visual or physics expansion")
	var poses:Array[Transform3D]=[Transform3D(Basis.from_euler(Vector3(.12,.27,-.3)).scaled(Vector3(2,.7,1.3)),Vector3(-31.5,-2,2)),Transform3D(Basis(Vector3(-1,0,0),Vector3(.3,2,0),Vector3(.2,.1,1)),Vector3(-4,-.5,7)),Transform3D(Basis.IDENTITY,Vector3(-.25,-31,31))]
	var values:=PackedFloat32Array()
	for pose:Transform3D in poses:values.append_array(packed(pose))
	check(source.upsert_instances(PackedInt64Array([2,11,51]),values),"affine mirrored and negative-owner records retain stable identities")
	var packet:PackedByteArray=source.capture_region(REGION)
	var checksum:=packet.slice(packet.size()-32)
	var page:=decoded(packet)
	check(page!=null and page.stats().instances==3,"exact canonical packet decodes into compact read-only records")
	if page==null:source.free();quit(1);return
	var first:Dictionary=page.page(0,2);var final:Dictionary=page.page(2,2)
	check(first.ids==PackedInt64Array([2,11]) and final.ids==PackedInt64Array([51]) and first.next==2 and not first.complete and final.complete,"bounded publication retains ordered canonical IDs and complete range")
	check(page.page(-1,2).is_empty() and page.page(0,0).is_empty() and page.page(0,1025).is_empty() and page.page(4,1).is_empty() and page.page(9223372036854775807,1).is_empty(),"invalid and oversized publication requests reject before allocation")
	check(page.page(3,1).complete and page.page(3,1).ids.is_empty(),"end cursor is an explicit empty complete range")
	var multimesh:MultiMesh=page.create_multimesh(mesh,0,3)
	check(multimesh!=null and multimesh.mesh==mesh and multimesh.instance_count==3 and not multimesh.use_colors and not multimesh.use_custom_data,"render page shares exact source geometry materials and imported LODs without baking")
	var expected_values:=values.duplicate()
	for index in poses.size():
		expected_values[index*12+3]-=first.origin.x;expected_values[index*12+7]-=first.origin.y;expected_values[index*12+11]-=first.origin.z
	check(page.page(0,3).transforms.to_byte_array()==expected_values.to_byte_array(),"packed GPU layout preserves every source basis component and local origin")
	if DisplayServer.get_name()!="headless":
		var parity:=true
		for index in poses.size():
			var actual:=multimesh.get_instance_transform(index);actual.origin+=first.origin
			parity=parity and actual.is_equal_approx(poses[index])
		check(parity,"actual renderer reads back exact affine transforms including mirrored instances")
	var expected_bounds:AABB=poses[0]*mesh.get_aabb()
	for index in range(1,poses.size()):expected_bounds=expected_bounds.merge(poses[index]*mesh.get_aabb())
	var actual_bounds:=multimesh.custom_aabb;actual_bounds.position+=first.origin
	check(actual_bounds.is_equal_approx(expected_bounds),"culling bounds include actual transformed source mesh extents")
	check(page.create_multimesh(null,0,1)==null and page.create_multimesh(mesh,3,1)==null and page.create_multimesh(mesh,0,1025)==null,"invalid empty or unbounded GPU uploads produce no resource")
	check(not page.load_packet(packet,checksum,ASSET,REGION) and page.page(0,3).ids==PackedInt64Array([2,11,51]),"published payload is immutable rather than silently replaced")
	var bad:RefCounted=ClassDB.instantiate("NativeModelRenderPage")
	check(not bad.load_packet(packet,checksum,"wrong/asset",REGION) and not bad.load_packet(packet,checksum,ASSET,Vector3i.ZERO),"wrong asset and region reject even with a matching outer digest")
	var corrupt:=packet.duplicate();corrupt[50]^=1
	check(decoded(corrupt)==null,"corrupt body cannot borrow the original checksum")
	corrupt=packet.duplicate();corrupt[24]^=1;var outer:=corrupt.slice(0,corrupt.size()-32);outer.append_array(digest(outer))
	check(decoded(outer)==null,"valid outer hash cannot hide damaged inner packet")
	var record_start:=40+ASSET.to_utf8_buffer().size()
	corrupt=packet.duplicate();corrupt.encode_float(record_start+8+3*4,32)
	check(decoded(resigned(corrupt))==null,"validly signed out-of-region transform rejects")
	corrupt=packet.duplicate();corrupt.encode_float(record_start+8,NAN)
	check(decoded(resigned(corrupt))==null,"non-finite transform rejects before rendering")
	corrupt=packet.duplicate();corrupt.encode_s64(record_start+56,2)
	check(decoded(resigned(corrupt))==null,"duplicate stable identity rejects")
	corrupt=packet.duplicate()
	for component in 3:corrupt.encode_float(record_start+8+component*4,0)
	check(decoded(resigned(corrupt))==null,"singular basis rejects even with valid inner and outer hashes")
	var empty_packet:PackedByteArray=source.capture_region(Vector3i(1,0,0))
	var empty:=decoded(empty_packet,Vector3i(1,0,0))
	check(empty!=null and empty.page(0,1).complete and empty.create_multimesh(mesh,0,1)==null,"empty canonical owner has explicit coverage without an empty draw")
	empty=null;bad=null;page=null;multimesh=null
	check(counter.live_pages()==0,"direct decoding releases every payload")
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld")
	blocks.set_cells(PackedInt32Array([0,0,0,1]))
	var codec:RefCounted=ClassDB.instantiate("NativeStructuresSnapshot");codec.configure_assets(PackedStringArray([ASSET]))
	var raw:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var archive:RefCounted=ClassDB.instantiate("NativeRegionWorldArchive");archive.configure(raw,codec,true)
	var path:=ProjectSettings.globalize_path(output.path_join("fixture_%d.trw"%OS.get_process_id()))
	check(archive.acquire(path) and archive.publish(path,archive.encode({"terrain":PackedByteArray([1]),"structures":codec.encode(blocks.capture_snapshot(),{ASSET:source.capture_snapshot()})}))==OK,"isolated read-only render fixture publishes")
	var saved_hash:=FileAccess.get_sha256(path)
	var index:Dictionary=archive.published_model_index(ASSET)
	check(source.unload_region(packet) and source.stats().instances==0,"canonical props retire before requesting far render data")
	var reservation:int=archive.region_read_stats().model_reservation_per_request
	check(archive.start_region_reads(2,reservation*2),"render path reuses one bounded archive worker")
	check(archive.request_model_render_read(ASSET,REGION,checksum,PackedByteArray(),1)==0 and archive.request_model_render_read("absent",REGION,checksum,index.checkpoint,1)==0,"render requests require a registered prototype and certified checkpoint")
	var ticket:int=archive.request_model_render_read(ASSET,REGION,checksum,index.checkpoint,7)
	var ticket_second:int=archive.request_model_render_read(ASSET,REGION,checksum,index.checkpoint,8)
	check(ticket>0 and ticket_second>0 and archive.request_model_render_read(ASSET,REGION,checksum,index.checkpoint,9)==0,"read pressure respects shared request and byte limits")
	var deadline:=Time.get_ticks_msec()+10000
	while archive.region_read_stats().model_render_completed<2 and Time.get_ticks_msec()<deadline:await process_frame
	check(archive.take_survey_region_read(ticket).is_empty() and archive.take_model_region_read(ticket).is_empty() and archive.poll_model_region_reads(2).is_empty(),"unrelated survey and gameplay consumers cannot steal render completions")
	var result:=await wait_for(archive,ticket)
	page=result.get("render_page")
	check(result.get("ok",false) and result.get("checkpoint_verified",false) and result.epoch==7 and page!=null and not result.has("bytes") and not result.has("survey"),"worker returns a verified native payload without gameplay bytes or worker-owned Godot objects")
	check(source.stats().instances==0 and source.collision_stats().resident_bodies==0 and page.page(0,3).transforms.to_byte_array()==expected_values.to_byte_array(),"never-near archived props have identical render transforms without gameplay hydration")
	check(archive.discard_survey_region_read(ticket_second) and await wait_empty(archive) and archive.region_read_stats().reserved_bytes==0 and archive.region_read_stats().retained_checkpoint_keys==0,"consumption and cancellation release bytes and checkpoint pins")
	result.clear();page=null
	check(counter.live_pages()==0,"completed native payloads have a single caller lifetime")
	var wrong:=checksum.duplicate();wrong[0]^=1
	ticket=archive.request_model_render_read(ASSET,REGION,wrong,index.checkpoint,20)
	result=await wait_for(archive,ticket)
	check(not result.get("ok",true) and not result.has("render_page") and not result.has("bytes"),"checkpoint mismatch cannot silently fall back to a newer model revision")
	result.clear()
	var lifecycle_ok:=true
	for cycle in 24:
		ticket=archive.request_model_render_read(ASSET,REGION,checksum,index.checkpoint,30+cycle)
		lifecycle_ok=lifecycle_ok and ticket>0
		if cycle%3==1:
			deadline=Time.get_ticks_msec()+10000
			while archive.region_read_stats().model_render_completed<1 and Time.get_ticks_msec()<deadline:await process_frame
		if cycle%3==2:
			result=await wait_for(archive,ticket);lifecycle_ok=lifecycle_ok and result.get("ok",false);result.clear()
		else:lifecycle_ok=archive.discard_survey_region_read(ticket) and lifecycle_ok
		lifecycle_ok=await wait_empty(archive) and counter.live_pages()==0 and archive.region_read_stats().retained_checkpoint_keys==0 and lifecycle_ok
	check(lifecycle_ok,"24 pending completed and consumed cycles release native pages and reservations")
	check(FileAccess.get_sha256(path)==saved_hash and source.stats().instances==0,"render reads leave saved world and gameplay residency untouched")
	var reader_stats:Dictionary=archive.region_read_stats()
	archive.join_region_reads();archive.release();archive=null
	check(counter.live_pages()==0,"archive shutdown leaves no native visual payload")
	check(source.restore_region(packet) and source.clear_instances(),"source fixture can resume normal authoring")
	var dense_ids:=PackedInt64Array();var dense_values:=PackedFloat32Array()
	dense_ids.resize(100000);dense_values.resize(1200000)
	for index_dense in 100000:
		dense_ids[index_dense]=index_dense+1
		var pose:=packed(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.1),Vector3((index_dense%100)*.25,1+(index_dense/10000)*.25,((index_dense/100)%100)*.25)))
		for component in 12:dense_values[index_dense*12+component]=pose[component]
	check(source.upsert_instances(dense_ids,dense_values),"100000-instance canonical region is admitted")
	var dense_packet:PackedByteArray=source.capture_region(Vector3i.ZERO)
	var began:=Time.get_ticks_usec();page=decoded(dense_packet,Vector3i.ZERO);var decode_us:=Time.get_ticks_usec()-began
	check(page!=null and page.stats().instances==100000 and page.stats().allocated_record_bytes==5600000 and page.stats().payload_bytes<reservation,"dense immutable payload fits the existing archive reservation")
	var visited:=0;var dense_ok:=true;var chunks:=0
	while visited<100000:
		var chunk:Dictionary=page.page(visited,1024)
		dense_ok=dense_ok and chunk.ids==dense_ids.slice(visited,chunk.next) and chunk.transforms.to_byte_array()==dense_values.slice(visited*12,chunk.next*12).to_byte_array()
		visited=chunk.next;chunks+=1
	check(dense_ok and chunks==98,"dense publication visits 98 bounded exact pages instead of one giant GPU upload")
	multimesh=page.create_multimesh(mesh,0,1024)
	var tail:MultiMesh=page.create_multimesh(mesh,99328,1024)
	check(multimesh.instance_count==1024 and tail.instance_count==672,"GPU publication honors the 1024-instance cap and partial final page")
	if DisplayServer.get_name()!="headless":
		check(packed(multimesh.get_instance_transform(1023)).to_byte_array()==dense_values.slice(1023*12,1024*12).to_byte_array() and packed(tail.get_instance_transform(671)).to_byte_array()==dense_values.slice(99999*12,100000*12).to_byte_array(),"dense GPU pages retain exact boundary transforms")
	var dense_stats:Dictionary=page.stats();page=null;multimesh=null;tail=null
	archive=ClassDB.instantiate("NativeRegionWorldArchive");archive.configure(raw,codec,true)
	var dense_path:=ProjectSettings.globalize_path(output.path_join("dense_%d.trw"%OS.get_process_id()))
	check(archive.acquire(dense_path) and archive.publish(dense_path,archive.encode({"terrain":PackedByteArray([1]),"structures":codec.encode(blocks.capture_snapshot(),{ASSET:source.capture_snapshot()})}))==OK and archive.start_region_reads(2,reservation*2),"dense source uses the same bounded archive worker path")
	index=archive.published_model_index(ASSET)
	var lease:int=archive.retain_read_checkpoint(ASSET,index.checkpoint)
	var moved:=packed(Transform3D(Basis.IDENTITY,Vector3(12,2,12)))
	check(lease>0 and source.upsert_instances(PackedInt64Array([1]),moved) and archive.publish(dense_path,archive.encode({"terrain":PackedByteArray([1]),"structures":codec.encode(blocks.capture_snapshot(),{ASSET:source.capture_snapshot()})}))==OK,"new model version publishes while old render checkpoint remains pinned")
	ticket=archive.request_model_render_read(ASSET,Vector3i.ZERO,dense_packet.slice(dense_packet.size()-32),index.checkpoint,100)
	result=await wait_for(archive,ticket);page=result.get("render_page")
	check(result.get("ok",false) and page!=null and page.page(0,1).transforms.to_byte_array()==dense_values.slice(0,12).to_byte_array() and source.get_instance(1)==moved,"dense worker retains requested historical geometry rather than newer live transforms")
	var worker_decode_us:int=result.get("render_decode_usec",-1)
	result.clear();page=null
	check(archive.release_read_checkpoint(lease) and counter.live_pages()==0,"historical render lifetime releases explicit and request-owned pins")
	var block_packet:PackedByteArray=blocks.capture_region(Vector3i.ZERO)
	var block_index:Dictionary=archive.published_region_index()
	var block_ticket:int=archive.request_survey_region_read(Vector3i.ZERO,block_packet.slice(block_packet.size()-32),block_index.checkpoint,101)
	deadline=Time.get_ticks_msec()+10000
	while archive.region_read_stats().survey_completed<1 and Time.get_ticks_msec()<deadline:await process_frame
	check(archive.take_model_render_region_read(block_ticket).is_empty() and archive.take_survey_region_read(block_ticket).get("ok",false),"render consumer cannot steal another service's survey ticket")
	index=archive.published_model_index(ASSET)
	var current_packet:PackedByteArray=source.capture_region(Vector3i.ZERO)
	ticket=archive.request_model_render_read(ASSET,Vector3i.ZERO,current_packet.slice(current_packet.size()-32),index.checkpoint,102)
	archive.join_region_reads()
	check(ticket>0 and archive.region_read_stats().model_render_completed==1 and counter.live_pages()==1,"joined worker leaves explicit ownership of unconsumed native result")
	archive.release();archive=null
	check(counter.live_pages()==0,"destroying archive releases an unread dense payload without a Godot object leak")
	source.free();blocks.free()
	check(counter.live_pages()==0,"pressure teardown releases every native payload")
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"dense_decode_us":decode_us,"worker_dense_decode_us":worker_decode_us,"dense":dense_stats,"reader":reader_stats,"rendered":DisplayServer.get_name()!="headless"},"  "))
	print("MODEL_RENDER_PAGES checks=",checks," failures=",failures)
	quit(1 if failures else 0)
