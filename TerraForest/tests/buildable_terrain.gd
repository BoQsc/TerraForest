extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var checks:=0
func check(valid:bool,label:String)->bool:
	checks+=1
	if not valid:failures+=1
	print("PASS " if valid else "FAIL ",label)
	return valid
func heights(core:RefCounted,points:PackedVector3Array)->PackedFloat32Array:
	var values:=PackedFloat32Array()
	for first in range(0,points.size(),256):
		var batch:PackedVector3Array=points.slice(first,mini(first+256,points.size()))
		var request:=Codec.command(37,[batch.size()]);request.append_array(batch.to_byte_array())
		var response:PackedByteArray=core.execute(request)
		if not Codec.reply_ok(response):return PackedFloat32Array()
		for index in batch.size():values.append(response.decode_float(12+index*8))
	return values
func measure(values:PackedFloat32Array)->Dictionary:
	var contact:=0;var gap_sum:=0.0;var sites:=values.size()/9
	for first in range(0,values.size(),9):
		var low:=INF;var high:=-INF
		for index in range(first,first+9):low=minf(low,values[index]);high=maxf(high,values[index])
		var bottom:=maxf(floorf(values[first+4]),ceilf(high-.20-.00001))
		var gap:=maxf(0,bottom-high);gap_sum+=gap
		if gap<=.03001 and bottom-low<=.20001:contact+=1
	return {"sites":sites,"contact":contact,"contact_fraction":float(contact)/sites,"mean_air_gap":gap_sum/sites}
func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var report:Array=[]
	var points:=PackedVector3Array()
	for across in range(320,1681,17):
		for along in range(320,1681,17):
			for offset_x:float in [.08,.5,.92]:
				for offset_z:float in [.08,.5,.92]:points.append(Vector3(across+offset_x,0,along+offset_z))
	for seed_value:int in [0,42,1703,2147483647]:
		var original:RefCounted=ClassDB.instantiate("TerrainCore")
		var revised:RefCounted=ClassDB.instantiate("TerrainCore")
		original.execute(Codec.command(6,[seed_value,17]))
		var began:=Time.get_ticks_usec()
		check(Codec.reply_ok(revised.execute(Codec.command(6,[seed_value,20]))),"build-friendly generator initializes seed %d"%seed_value)
		var initialize_ms:=(Time.get_ticks_usec()-began)/1000.0
		began=Time.get_ticks_usec();var before:=heights(original,points);var before_ms:=(Time.get_ticks_usec()-began)/1000.0
		began=Time.get_ticks_usec();var after:=heights(revised,points);var after_ms:=(Time.get_ticks_usec()-began)/1000.0
		if not check(before.size()==points.size() and after.size()==points.size(),"bounded native terrain survey is complete"):continue
		var before_fit:=measure(before);var after_fit:=measure(after);var displacement:=0.0
		for index in before.size():displacement=maxf(displacement,absf(before[index]-after[index]))
		check(after_fit.contact_fraction>before_fit.contact_fraction+.04,"generator increases close-fitting block footprints by over four percentage points")
		check(after_fit.mean_air_gap<before_fit.mean_air_gap,"generator reduces average grid-to-ground air gap")
		check(displacement<=.361,"terrain height adjustment remains below 36 cm")
		var baseline_cache:Dictionary=original.geometry_cache_key(800,1296,16,1)
		check(baseline_cache!=revised.geometry_cache_key(800,1296,16,1),"new terrain never reuses the old mesh cache identity")
		var saved:PackedByteArray=revised.execute(Codec.command(4,[3])).slice(12)
		var restored:RefCounted=ClassDB.instantiate("TerrainCore")
		var restore:=Codec.command(5);restore.append_array(saved)
		check(Codec.reply_ok(restored.execute(restore)) and heights(restored,points.slice(0,256))==after.slice(0,256),"saved new profile regenerates identical ground")
		original.execute(Codec.command(6,[seed_value,19]));revised.execute(Codec.command(6,[seed_value,21]))
		var shore:=PackedVector3Array()
		for distance in range(0,2001,40):
			for inset:int in [0,80,140,239]:shore.append_array(PackedVector3Array([Vector3(inset,0,distance),Vector3(2000-inset,0,distance),Vector3(distance,0,inset),Vector3(distance,0,2000-inset)]))
		check(heights(original,shore)==heights(revised,shore),"coastal profile retains the old coastline and beach heights")
		var lakes:PackedByteArray=original.execute(Codec.command(27))
		check(lakes==revised.execute(Codec.command(27)),"lake definitions stay identical")
		var banks:=PackedVector3Array()
		for lake_index in lakes.decode_u32(12):
			var offset:=16+lake_index*44;var center:=Vector3(lakes.decode_float(offset+32),0,lakes.decode_float(offset+40))
			for across in range(-32,33,8):
				for along in range(-32,33,8):banks.append(center+Vector3(across,0,along))
		check(heights(original,banks)==heights(revised,banks),"lake interiors stay unchanged")
		var row:={"seed":seed_value,"before":before_fit,"after":after_fit,"max_displacement":displacement,"initialize_ms":initialize_ms,"before_survey_ms":before_ms,"after_survey_ms":after_ms}
		report.append(row);print("BUILDABLE_MEASURE ",JSON.stringify(row))
	var edited:RefCounted=ClassDB.instantiate("TerrainCore");edited.execute(Codec.command(6,[1703,21]))
	var center:=Vector3(800,0,1310);center.y=heights(edited,PackedVector3Array([center]))[0]-.5
	check(Codec.reply_ok(edited.execute(Codec.brush(center,center,1.5,0,false,1))),"mining edits the new native field")
	var snapshot:PackedByteArray=edited.execute(Codec.command(4,[3])).slice(12)
	var store:RefCounted=ClassDB.instantiate("NativeTerrainRegionStore")
	var folder:="user://buildable_storage_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	check(store.open_store(ProjectSettings.globalize_path(folder),true),"isolated binary region store opens")
	var reference:PackedByteArray=store.publish_snapshot(snapshot)
	check(reference.size()==40 and store.describe_snapshot(reference).generator==21 and store.expand_snapshot(reference)==snapshot,"edited coastal profile roundtrips through binary region storage")
	store.close()
	var report_root:="res://reports"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--terrain-report-dir="):report_root=argument.trim_prefix("--terrain-report-dir=")
	DirAccess.make_dir_recursive_absolute(report_root.path_join("buildable_terrain"))
	var metrics:=FileAccess.open(report_root.path_join("buildable_terrain/metrics.json"),FileAccess.WRITE)
	var summary:=FileAccess.open(report_root.path_join("buildable_terrain.json"),FileAccess.WRITE)
	if metrics==null or summary==null:
		failures+=1;print("FAIL terrain check report destination is not writable")
	else:
		metrics.store_string(JSON.stringify(report,"  "))
		summary.store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":report}))
	print("BUILDABLE_TERRAIN checks=",checks," failures=",failures);quit(1 if failures else 0)
