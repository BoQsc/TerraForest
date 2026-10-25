extends "res://tests/buildable_terrain.gd"
func embedding(values:PackedFloat32Array,reference:PackedFloat32Array)->Dictionary:
	var count:=0;var shallow:=0;var deep:=0;var total:=0.0;var worst:=0.0;var gap_total:=0.0;var large_gaps:=0
	for first in range(0,values.size(),9):
		var raw:=Array(reference.slice(first,first+9))
		if raw.max()-raw.min()>.12 or raw.max()>75:continue
		var footprint:=Array(values.slice(first,first+9))
		var bottom:=maxf(floorf(values[first+4]),ceilf(footprint.max()-.2-.00001))
		var lower:=bottom-1;var lower_burial:float=footprint.max()-lower;var upper_gap:float=maxf(0,bottom-footprint.min())
		if lower>=floorf(values[first+4])-.00001 and upper_gap>.10 and lower_burial<=.60001 and lower_burial<=upper_gap*1.5+.00001:bottom=lower
		var burial:=maxf(0,footprint.max()-bottom)
		var gap:=maxf(0,bottom-footprint.min());gap_total+=gap
		count+=1;total+=burial;worst=maxf(worst,burial)
		if burial<=.25 and gap<=.1:shallow+=1
		if burial>.60:deep+=1
		if gap>.1:large_gaps+=1
	return {"sites":count,"shallow":shallow,"over_60cm":deep,"mean_burial":total/maxi(1,count),"worst_burial":worst,"mean_gap":gap_total/maxi(1,count),"gaps_over_10cm":large_gaps}
func _initialize()->void:
	var points:=PackedVector3Array()
	for across in range(320,1681,17):
		for along in range(320,1681,17):
			for offset_x:float in [.08,.5,.92]:
				for offset_z:float in [.08,.5,.92]:points.append(Vector3(across+offset_x,0,along+offset_z))
	var reports:Array=[]
	for seed_value in [0,42,1703,2147483647]:
		var fields:Array=[]
		for profile in [17,20,22]:
			var core:RefCounted=ClassDB.instantiate("TerrainCore")
			check(Codec.reply_ok(core.execute(Codec.command(6,[seed_value,profile]))),"immutable terrain profile initializes")
			fields.append(heights(core,points))
		var old:=embedding(fields[1],fields[0]);var revised:=embedding(fields[2],fields[0])
		check(revised.mean_burial<old.mean_burial and revised.shallow>old.shallow,"native generation reduces burial and increases shallow-contact sites")
		var displacement:=0.0;var maximum_raise:=0.0;var maximum_cut:=0.0
		for index in points.size():
			var change:float=fields[2][index]-fields[0][index]
			displacement=maxf(displacement,absf(change));maximum_raise=maxf(maximum_raise,change);maximum_cut=maxf(maximum_cut,-change)
		check(displacement<=.55,"soft terrain correction stays within 55 cm of the original field")
		check(maximum_raise>.1 and maximum_cut>.1,"generation corrects both low and high ground rather than only burying blocks")
		var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,23]))
		var saved:PackedByteArray=core.execute(Codec.command(4,[3])).slice(12)
		var restored:RefCounted=ClassDB.instantiate("TerrainCore");var command:=Codec.command(5);command.append_array(saved)
		check(Codec.reply_ok(restored.execute(command)) and heights(restored,points.slice(0,256))==heights(core,points.slice(0,256)),"new profile restores without changing prior generator identities")
		var coast:=PackedVector3Array([Vector3(0,0,1000),Vector3(80,0,1000),Vector3(140,0,1000),Vector3(1999,0,1000)])
		restored.execute(Codec.command(6,[seed_value,21]))
		check(heights(core,coast)==heights(restored,coast),"coastal boundary stays unchanged")
		reports.append({"seed":seed_value,"before":old,"after":revised,"max_displacement":displacement,"maximum_raise":maximum_raise,"maximum_cut":maximum_cut})
	DirAccess.make_dir_recursive_absolute("res://reports/road_normalization")
	FileAccess.open("res://reports/road_normalization/embedding.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"cases":reports},"  "))
	print("EMBEDDING_TERRAIN failures=",failures);quit(1 if failures else 0)
