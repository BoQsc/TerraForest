# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var folder:=""
var catalog:=PackedByteArray()
const ORIGIN=Vector3i(200,40,200)
const SIZE=Vector3i(4,4,4)

func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--water-patch-dir="):folder=argument.trim_prefix("--water-patch-dir=")
	run.call_deferred()

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func fixture(rows:Array)->PackedByteArray:
	var records:=PackedByteArray();var vacancies:=PackedByteArray();var total:=0
	var prototype:=PackedByteArray();prototype.resize(9076);prototype.fill(0)
	prototype.encode_u32(8,1);prototype.encode_u32(12,1)
	for sample in 512:prototype.encode_u16(18+sample*12,500)
	for sample in 729:prototype.encode_float(6160+sample*4,1.0)
	for row:Dictionary in rows:
		var record:=prototype.duplicate();var coordinate:Vector3i=row.coordinate
		record.encode_u64(0,(coordinate.x<<24)|(coordinate.y<<12)|coordinate.z)
		record.encode_u32(8,0 if row.get("invalid",false) else 1)
		record.encode_u32(12,1|(int(row.get("ocean",0))<<2))
		for sample:int in row.get("water",{}):
			var amount:int=row.water[sample];record.encode_u64(20+sample*12,amount);total+=amount
		if row.has("dense"):
			for sample in 512:record.encode_u64(20+sample*12,row.dense);total+=int(row.dense)
		records.append_array(record)
		var missing:Dictionary=row.get("vacancies",{});var keys:=missing.keys();keys.sort()
		var encoded:=PackedByteArray();encoded.resize(4+keys.size()*8);encoded.encode_u32(0,keys.size())
		for index in keys.size():encoded.encode_u32(4+index*8,keys[index]);encoded.encode_u32(8+index*8,missing[keys[index]])
		vacancies.append_array(encoded)
	var data:=PackedByteArray();data.resize(32);data.fill(0)
	data.encode_u32(0,0x31575256);data.encode_u32(4,13);data.encode_u32(8,catalog.size());data.encode_u32(12,rows.size());data.encode_u64(16,total);data.encode_u64(24,rows.size()*8+vacancies.size())
	data.append_array(catalog);data.append_array(records)
	var contacts:=PackedByteArray();contacts.resize(rows.size()*8);contacts.fill(0)
	data.append_array(contacts);data.append_array(vacancies);return data

func owner(rows:Array=[])->RefCounted:
	var water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
	check(water.restore_snapshot(fixture(rows)),"valid isolated water fixture: "+str(rows.size())+" regions")
	return water

func capture(water:RefCounted,origin:=ORIGIN,size:=SIZE)->PackedByteArray:
	var token:Dictionary=water.water_patch_state()
	return water.capture_water_patch(origin,size,token.revision,token.owner)

func restore(water:RefCounted,data:PackedByteArray)->Dictionary:
	var token:Dictionary=water.water_patch_state()
	return water.restore_water_patch(data,token.revision,token.owner)

func seal(data:PackedByteArray)->PackedByteArray:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(data.slice(0,data.size()-32))
	var output:=data.slice(0,data.size()-32);output.append_array(hash.finish());return output

func write(name:String,data:PackedByteArray)->void:
	var file:=FileAccess.open(folder.path_join(name),FileAccess.WRITE)
	check(file!=null,"write isolated "+name)
	if file!=null:file.store_buffer(data);file.close()

func publish(water:RefCounted)->bool:
	for step in 512:
		var batch:Dictionary=water.next_mesh_batch()
		if batch.is_empty():return true
		if batch.get("complete",false) and not water.commit_mesh_batch(batch.batch):return false
	return false

func run()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
	catalog=ClassDB.instantiate("NativeLakeCatalog").encode([])
	if "--reopen" in OS.get_cmdline_user_args():
		var water:=owner()
		check(water.restore_snapshot(FileAccess.get_file_as_bytes(folder.path_join("current.bin"))),"fresh-process current water loads")
		check(restore(water,FileAccess.get_file_as_bytes(folder.path_join("baseline.bin"))).ok,"fresh-process scoped baseline restores")
		check(water.capture_snapshot(catalog)==FileAccess.get_file_as_bytes(folder.path_join("expected.bin")),"fresh-process exact quantities vacancies and outside cells")
		check(publish(water),"fresh-process changed water publishes through ordinary mesh batches")
		finish();return
	var initial:=[{"coordinate":Vector3i(25,5,25),"water":{0:100000,1:125000,7:25000},"vacancies":{0:3000,7:700}},{"coordinate":Vector3i(26,5,25),"water":{0:9000}}]
	var water:=owner(initial)
	var baseline:=capture(water)
	check(baseline.size()==128 and baseline.decode_u32(12)==2 and water.validate_water_patch(baseline),"sparse water patch represents 64 half-metre cells using two nonempty records")
	check(baseline.decode_u64(40)==225000 and baseline.decode_u32(68)==3000,"captured quantity and bucket vacancy channels")
	var original:PackedByteArray=water.capture_snapshot(catalog);var token:Dictionary=water.water_patch_state()
	check(capture(water)==baseline and water.capture_snapshot(catalog)==original and water.water_patch_state()==token,"capture is deterministic and read-only")
	for pair:Array in [[Vector3i(-1,40,200),SIZE],[ORIGIN,Vector3i.ZERO],[Vector3i(200,1,200),SIZE],[ORIGIN,Vector3i(257,1,1)],[ORIGIN,Vector3i(128,128,128)],[Vector3i(3999,40,200),SIZE],[Vector3i(200,508,200),SIZE],[Vector3i(1,40,1),Vector3i(256,1,256)]]:
		check(capture(water,pair[0],pair[1]).is_empty(),"invalid or over-budget cell/region box rejected "+str(pair))
	check(water.capture_water_patch(ORIGIN,SIZE,token.revision+1,token.owner).is_empty() and water.capture_water_patch(ORIGIN,SIZE,token.revision,token.owner+1).is_empty(),"capture rejects stale or foreign token")
	check(water.brush(Vector3(100.25,20.25,100.25),0,-5000)==5000,"ordinary local water edit changes selected cell")
	check(not water.restore_water_patch(baseline,token.revision,token.owner).ok,"edit invalidates prior patch token")
	var current_rows:=[{"coordinate":Vector3i(25,5,25),"water":{0:4000,1:6000,7:27000},"vacancies":{0:6000,1:50,7:900}},{"coordinate":Vector3i(26,5,25),"water":{0:18000}}]
	check(water.restore_snapshot(fixture(current_rows)),"current edited quantity/vacancy fixture")
	var current:PackedByteArray=water.capture_snapshot(catalog)
	var bad:=baseline.duplicate();bad[bad.size()-1]^=1
	check(not water.validate_water_patch(bad) and not restore(water,bad).ok and water.capture_snapshot(catalog)==current,"bad checksum rejects without altering water")
	for offset:int in [0,4,8,12,16,20,24,28,32,36,40,48,56,64,68,72]:
		bad=baseline.duplicate();bad.encode_u32(offset,0xffffffff)
		check(not water.validate_water_patch(seal(bad)) and not restore(water,seal(bad)).ok and water.capture_snapshot(catalog)==current,"malformed water field rejected atomically "+str(offset))
	check(not restore(water,baseline.slice(0,baseline.size()-1)).ok and not restore(water,baseline+PackedByteArray([0])).ok,"truncated and extended patches rejected")
	bad=baseline.duplicate();bad.encode_u32(80,0)
	check(not water.validate_water_patch(seal(bad)),"duplicate sparse sample indices rejected")
	bad=baseline.duplicate();bad.encode_u64(72,0);bad.encode_u32(68,0);bad.encode_u64(40,125000)
	check(not water.validate_water_patch(seal(bad)),"redundant empty sparse records rejected")
	token=water.water_patch_state()
	check(not water.restore_water_patch(baseline,token.revision,token.owner+1).ok,"foreign live water owner rejected")
	var result:=restore(water,baseline)
	check(result.ok and result.changes==2 and result.regions==1 and result.coordinates==PackedInt32Array([25,5,25]),"only changed selected cells and owner region are restored")
	var expected_rows:=[{"coordinate":Vector3i(25,5,25),"water":{0:100000,1:125000,7:27000},"vacancies":{0:3000,7:900}},{"coordinate":Vector3i(26,5,25),"water":{0:18000}}]
	var expected_owner:=owner(expected_rows);var expected:PackedByteArray=expected_owner.capture_snapshot(catalog)
	check(water.capture_snapshot(catalog)==expected and water.statistics().water_ml==270000,"outside quantities and vacancies survive, including same-region cells")
	token=water.water_patch_state()
	check(restore(water,baseline).changes==0 and water.water_patch_state()==token,"no-op restoration preserves token and queues")
	check(publish(water) and water.statistics().query_cache_bytes>0,"restored volume reaches normal mesh/picking publication")
	check(capture(water)==baseline,"mesh publication does not alter authoritative cell values")
	if not folder.is_empty():
		write("current.bin",current);write("baseline.bin",baseline);write("expected.bin",expected)
	var dry:=owner();var dry_patch:=capture(dry)
	check(dry_patch.size()==96 and dry_patch.decode_u64(40)==0,"absent inland region captures explicit dry baseline in 96 bytes")
	check(dry.restore_snapshot(fixture(initial)) and restore(dry,dry_patch).ok,"dry baseline removes later in-region water and vacancies")
	check(dry.statistics().water_ml==34000 and capture(dry)==dry_patch,"dry reset preserves water outside the box")
	var visual:=owner([{"coordinate":Vector3i(25,5,25),"water":{0:125000}}])
	check(publish(visual) and visual.statistics().query_cache_bytes>0,"wet fixture has published picking geometry")
	check(restore(visual,dry_patch).ok and publish(visual) and visual.statistics().query_cache_bytes==0,"dry reset retires stale mesh and picking geometry")
	var fresh:=owner();result=restore(fresh,baseline)
	check(result.ok and fresh.statistics().water_ml==225000 and fresh.statistics().pending_regions==1,"missing inland owner admits selected volume and requests current terrain contacts")
	check(capture(fresh).is_empty() and restore(fresh,baseline).get("reason")=="unavailable","unknown occupancy is never certified as ready")
	var stale:=owner(initial);var stale_token:Dictionary=stale.water_patch_state();stale.restore_snapshot(stale.capture_snapshot(catalog))
	check(not stale.restore_water_patch(baseline,stale_token.revision,stale_token.owner).ok,"whole-world reload invalidates previous token")
	var pending:=owner([{"coordinate":Vector3i(25,5,25),"invalid":true,"water":{0:1000}}]);var pending_before:PackedByteArray=pending.capture_snapshot(catalog)
	check(capture(pending).is_empty() and restore(pending,baseline).get("reason")=="unavailable" and pending.capture_snapshot(catalog)==pending_before,"in-flight terrain contacts reject atomically")
	var busy:=owner(initial)
	check(busy.begin_fill(AABB(Vector3(100,20,100),Vector3(2,2,2)),21,Vector3(100.25,20.25,100.25),1000),"authored fill fixture starts")
	check(capture(busy).is_empty() and restore(busy,baseline).get("reason")=="busy","active fill cannot race a location reset")
	busy=owner(initial);var batch:Dictionary=busy.next_mesh_batch()
	check(not batch.is_empty() and restore(busy,baseline).get("reason")=="busy","pending render publication cannot be overwritten by reset")
	check(publish(busy),"ordinary publication drains before reset")
	check(restore(busy,baseline).ok,"reset resumes after mesh publication")
	var ocean:=owner();var ocean_token:Dictionary=ocean.water_patch_state();ocean.set_surrounding_ocean(true)
	check(ocean.water_patch_state().revision>ocean_token.revision and not restore(ocean,baseline).ok,"ocean-mode change invalidates token and mismatched patch")
	check(capture(ocean,Vector3i(8,72,2000),SIZE).is_empty(),"unresident implicit sea cannot be captured as dry")
	var above_sea:=capture(ocean,Vector3i(8,80,2000),SIZE)
	check(above_sea.size()==96 and above_sea.decode_u64(40)==0 and restore(ocean,above_sea).ok,"unresident coastal volume at or above the exact 40m sea ceiling is dry")
	check(capture(ocean,Vector3i(8,79,2000),SIZE).is_empty(),"volume crossing below the sea ceiling still requires residency")
	var ocean_rows:=[{"coordinate":Vector3i(1,9,250),"ocean":1,"water":{0:125000,7:100000}}]
	var pristine:=owner(ocean_rows);pristine.set_surrounding_ocean(true)
	var sea_patch:=capture(pristine,Vector3i(8,72,2000),Vector3i(1,1,1))
	var edited:=owner([{"coordinate":Vector3i(1,9,250),"ocean":1,"water":{0:50000,7:100000}}]);edited.set_surrounding_ocean(true)
	check(restore(edited,sea_patch).ok and edited.statistics().ocean_edited_regions==1 and edited.statistics().water_ml==225000,"partial sea reset retains explicit edited ownership and unselected quantity")
	var deferred:=owner();var packet:PackedByteArray=edited.capture_region_snapshot(Vector3i(1,9,250))
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(packet)
	check(deferred.register_deferred_regions(PackedInt32Array([1,9,250]),hash.finish()),"deferred edited sea fixture")
	deferred.set_surrounding_ocean(true)
	check(capture(deferred,Vector3i(8,72,2000),Vector3i.ONE).is_empty() and restore(deferred,sea_patch).get("reason")=="unavailable","deferred edit is not overwritten as missing water")
	check(deferred.restore_region_snapshot(Vector3i(1,9,250),packet,deferred.survey_revision_id(),true),"existing hydration path recovers exact deferred state")
	check(restore(deferred,sea_patch).ok and capture(deferred,Vector3i(8,72,2000),Vector3i.ONE)==sea_patch,"hydrated water can participate in scoped reset")
	var neighbor:=owner(initial);hash.start(HashingContext.HASH_SHA256);hash.update(packet)
	check(neighbor.register_deferred_regions(PackedInt32Array([1,9,250]),hash.finish()),"outside deferred edit fixture")
	var outside:Dictionary=neighbor.deferred_region_page(0,256)
	check(not capture(neighbor).is_empty() and restore(neighbor,dry_patch).ok and neighbor.deferred_region_page(0,256)==outside,"unrelated deferred edits remain unchanged and do not block scoped restoration")
	check(pristine.update_ocean_residency(Vector3(1900,36,1002),1).retired==1,"pristine sea moves into existing bounded ocean cache")
	check(capture(pristine,Vector3i(8,72,2000),Vector3i.ONE).is_empty() and restore(pristine,sea_patch).get("reason")=="unavailable","cached sea is not mistaken for empty water")
	pristine.update_ocean_residency(Vector3(6,36,1002),4)
	check(capture(pristine,Vector3i(8,72,2000),Vector3i.ONE)==sea_patch,"ordinary ocean-cache residency restores the patch source exactly")
	capacity_checks(baseline)
	large_patch()
	finish()

func capacity_checks(baseline:PackedByteArray)->void:
	var maximum:=owner([{"coordinate":Vector3i(26,5,25),"water":{0:1<<52}}])
	var before:PackedByteArray=maximum.capture_snapshot(catalog)
	check(restore(maximum,baseline).get("reason")=="quantity_capacity" and maximum.capture_snapshot(catalog)==before,"global quantity limit rejects without changing outside water")
	var rows:Array=[]
	for column in 16:
		for row in 256:rows.append({"coordinate":Vector3i(100+column,5,row)})
	var full:=owner(rows);before=full.capture_snapshot(catalog)
	check(full.statistics().regions==4096 and restore(full,baseline).get("reason")=="region_capacity" and full.capture_snapshot(catalog)==before,"full world-region capacity rejects without evicting unrelated regions")
	check(restore(full,capture(full)).ok,"full world still allows no-op dry baseline")

func large_patch()->void:
	var rows:Array=[]
	for column in range(32,40):
		for height in range(8,16):
			for row in range(32,40):rows.append({"coordinate":Vector3i(column,height,row),"dense":1})
	var water:=owner(rows);var origin:=Vector3i(256,64,256);var size:=Vector3i(64,64,64)
	var began:=Time.get_ticks_usec();var baseline:=capture(water,origin,size);var capture_us:=Time.get_ticks_usec()-began
	check(water.remove_bounds(AABB(Vector3(origin)*.5,Vector3(size)*.5))==262144,"maximum fixture empties 262144 actual water cells")
	began=Time.get_ticks_usec();var result:=restore(water,baseline);var restore_us:=Time.get_ticks_usec()-began
	check(result.ok and result.changes==262144 and result.regions==512 and capture(water,origin,size)==baseline,"maximum patch restores exact water across 512 regions")
	print("WATER_PATCH_MAX bytes=",baseline.size()," capture_us=",capture_us," restore_us=",restore_us)
	var dry:=owner();began=Time.get_ticks_usec();var empty:=capture(dry,origin,size);capture_us=Time.get_ticks_usec()-began
	began=Time.get_ticks_usec();result=restore(dry,empty);restore_us=Time.get_ticks_usec()-began
	check(empty.size()==96 and result.ok and result.changes==0 and dry.statistics().regions==0,"maximum dry region uses 96 bytes and allocates no water owners")
	print("WATER_PATCH_DRY bytes=",empty.size()," capture_us=",capture_us," restore_us=",restore_us)

func finish()->void:
	print("WATER_PATCH checks=",checks," failures=",failures)
	quit(1 if failures else 0)
