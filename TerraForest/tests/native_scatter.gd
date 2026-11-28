# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	var native=ClassDB.instantiate("NativeVegetationScatter")
	var reference: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/scatter_reference.json"))
	var failures:=0
	failures+=publication_checks(native)
	var ecosystem=load("res://addons/world_ecosystem/world_ecosystem.gd").new()
	for row: Dictionary in reference:
		ecosystem.seed=int(row.seed);ecosystem.density=row.density
		var integrated: Dictionary=ecosystem._candidates(Vector2i(int(row.x),int(row.z)))
		var actual: Dictionary=native.candidates(Vector2i(int(row.x),int(row.z)),int(row.seed),row.density)
		for field in ["points","ids","rotations","scales"]:
			if integrated[field].to_byte_array().hex_encode()!=row[field]: failures+=1;print("FAIL integrated bytes ",field)
			if actual[field].to_byte_array().hex_encode()!=row[field]:
				failures+=1;print("FAIL legacy bytes ",row.seed," ",row.x," ",row.z," ",row.density," ",field)
	for cell in [Vector2i(-1,0),Vector2i(32,0),Vector2i(0,-1),Vector2i(0,32)]:
		if not native.candidates(cell,1703,1.0).ids.is_empty(): failures+=1
	for density in [-1.0,2.0,NAN,INF]:
		if not native.candidates(Vector2i(12,20),1703,density).ids.is_empty(): failures+=1
	ecosystem.seed=1703;ecosystem.density=0.82
	var begin:=Time.get_ticks_usec()
	for sample in range(1000): ecosystem._candidates(Vector2i(12,20))
	var facade_us:=(Time.get_ticks_usec()-begin)/1000.0
	begin=Time.get_ticks_usec()
	for sample in range(1000): native.candidates(Vector2i(12,20),1703,0.82)
	var native_us:=(Time.get_ticks_usec()-begin)/1000.0
	ecosystem.free()
	print("NATIVE_SCATTER ",JSON.stringify({"legacy_cases":reference.size(),"byte_checks":reference.size()*8,"invalid_cases":8,"failures":failures,"facade_mean_us":facade_us,"native_mean_us":native_us}))
	quit(1 if failures else 0)

func publication_checks(native:RefCounted)->int:
	var failures:=0
	var cover:RefCounted=ClassDB.instantiate("NativeGroundCover")
	var prototype:=AABB(Vector3(-1,-.2,-2),Vector3(2,8,4))
	for count in [0,1,9,64]:
		var poses:Array[Transform3D]=[];var ids:=PackedInt64Array();var roots:Array[Transform3D]=[];var probes:Array[Transform3D]=[]
		var bounds:=AABB();var masks:Array=[];var road:=PackedByteArray()
		for kind in 4:masks.append(PackedByteArray())
		for index in count:
			var pose:=Transform3D(Basis.from_euler(Vector3(.1,index*.13,.2)).scaled(Vector3(1,1.5,2)),Vector3(index*3-90,index*.7,70-index*4))
			poses.append(pose);ids.append(index+1)
			bounds=pose*prototype if index==0 else bounds.merge(pose*prototype)
			var root_pose:=pose;root_pose.origin.y+=.2;roots.append(root_pose)
			probes.append(Transform3D(Basis.IDENTITY,pose.origin))
			for side in 8:probes.append(Transform3D(Basis.IDENTITY,pose.origin+Vector3(cos(side*TAU/8),0,sin(side*TAU/8))*4.0))
			for kind in 4:masks[kind].append(1 if index%(kind+3)==kind else 0)
			for side in 9:road.append(1 if (index+side)%17==0 else 0)
		var before:=poses.duplicate();var prepared:Dictionary=native.prepare_publication(poses,prototype)
		if prepared.bounds!=bounds or prepared.surface_roots!=roots or cover.boulder_road_probes(poses)!=probes or before!=poses:
			failures+=1;print("FAIL native publication probes count=",count," bounds=",prepared.bounds==bounds," roots=",prepared.surface_roots==roots," road=",cover.boulder_road_probes(poses)==probes," input=",before==poses)
			for index in count:
				if prepared.surface_roots[index]!=roots[index]:print("ROOT_DIFFERENCE ",index," ",var_to_bytes(prepared.surface_roots[index]).hex_encode()," ",var_to_bytes(roots[index]).hex_encode());break
		for disabled in 16:
			var selected:Array=[]
			for kind in 4:selected.append(PackedByteArray() if disabled&(1<<kind) else masks[kind])
			var expected_ids:=PackedInt64Array();var expected_poses:Array[Transform3D]=[]
			for index in count:
				var excluded:=false
				for mask:PackedByteArray in selected:excluded=excluded or (not mask.is_empty() and mask[index]!=0)
				if not excluded:expected_ids.append(ids[index]);expected_poses.append(poses[index])
			var actual:Dictionary=native.filter_publication(ids,poses,selected)
			if actual.ids!=expected_ids or actual.transforms!=expected_poses:failures+=1;print("FAIL native publication mask combination ",disabled)
		var combined:PackedByteArray=masks[0].duplicate();var original_mask:PackedByteArray=masks[0].duplicate()
		for index in count:
			if masks[1][index] or masks[2][index]:combined[index]=1
			for side in 9:
				if road[index*9+side]:combined[index]=1
		if cover.boulder_exclusion_mask(masks[0],masks[1],masks[2],road)!=combined or masks[0]!=original_mask:failures+=1;print("FAIL boulder publication mask")
	if not native.filter_publication(PackedInt64Array([1]),[],[PackedByteArray(),PackedByteArray(),PackedByteArray(),PackedByteArray()]).is_empty():failures+=1
	if not native.filter_publication(PackedInt64Array(),[],[PackedByteArray([1]),PackedByteArray(),PackedByteArray(),PackedByteArray()]).is_empty():failures+=1
	if not cover.boulder_exclusion_mask(PackedByteArray([0]),PackedByteArray(),PackedByteArray(),PackedByteArray([0])).is_empty():failures+=1
	print("NATIVE_PUBLICATION cases=75 failures=",failures)
	return failures
