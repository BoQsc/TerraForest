# SPDX-License-Identifier: 0BSD
extends SceneTree
const Catalog=preload("res://addons/structures/shape_catalog.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(blocks);blocks.set_process(false)
	var empty:PackedByteArray=blocks.capture_snapshot()
	var words_ok:=true
	for word in 65536:
		var decoded:Dictionary=blocks.decode_block(word)
		if not decoded.is_empty():words_ok=words_ok and blocks.encode_block(decoded.shape,decoded.rotation,decoded.material,decoded.appearance)==word
	check(words_ok,"all 65536 encodings: accepted words have a unique lossless decode")
	check(blocks.encode_block(37,0,0)==-1 and blocks.encode_block(1,4,0,0)==-1 and blocks.encode_block(31,24,0,0)==-1 and blocks.encode_block(1,0,0,8)==-1 and blocks.encode_block(1,0,0,4294967296)==-1,"shape, rotation and appearance bounds reject before narrowing")
	var legacy_ok:=true
	for shape in range(1,19):
		for rotation in Catalog.rotation_count(shape):
			for material in 4:
				var old:int=32768|((shape-9)<<8)|rotation|(material<<5) if shape>8 else (128 if shape==8 else shape)+rotation*8+material*32
				legacy_ok=legacy_ok and blocks.encode_block(shape,rotation,material)==old
	check(legacy_ok,"every legacy shape/orientation/material retains its byte identity")
	for shape in range(19,37):
		for rotation in 24:
			blocks.restore_snapshot(empty)
			var word:int=blocks.encode_block(shape,rotation,2,rotation%8)
			blocks.set_cells(PackedInt32Array([0,0,0,word]))
			var mesh:Mesh=blocks.preview_mesh(shape,rotation)
			var arrays:Array=mesh.surface_get_arrays(0)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var probes:=PackedVector3Array();var geometry_ok:=not indices.is_empty()
			for vertex in vertices:geometry_ok=geometry_ok and vertex.x>=-.00001 and vertex.y>=-.00001 and vertex.z>=-.00001 and vertex.x<=1.00001 and vertex.y<=1.00001 and vertex.z<=1.00001
			for index in range(0,indices.size(),3):
				var a:=vertices[indices[index]];var b:=vertices[indices[index+1]];var c:=vertices[indices[index+2]]
				var n:=(c-a).cross(b-a);geometry_ok=geometry_ok and n.length_squared()>1e-12 and n.normalized().dot(normals[indices[index]])>.999
				var center:=(a+b+c)/3;probes.append(center-n.normalized()*.0001);probes.append(center+n.normalized()*.0001)
			var samples:PackedByteArray=blocks.sample_solid(probes)
			for index in samples.size():geometry_ok=geometry_ok and samples[index]==(1 if index%2==0 else 0)
			check(geometry_ok,"shape %d orientation %d: grid bounds, winding and exact render/solid separation"%[shape,rotation])
	# Closed gables touching thin slopes at nonzero chunk coordinates previously
	# left micrometre slivers. Check actual joined output, not isolated previews.
	for pose in 4:
		blocks.restore_snapshot(empty)
		var joined:=PackedInt32Array()
		for row in 5:
			for step in 8:
				joined.append_array(PackedInt32Array([step+8,step+1,row+11,blocks.encode_block(35 if row in [0,4] else 15,pose,1,4)]))
		blocks.set_cells(joined);blocks.flush_bakes()
		var valid:=true;var triangles:=0
		for child in blocks.get_children():
			if child is MeshInstance3D:
				var arrays:Array=child.mesh.surface_get_arrays(0);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
				for i in range(0,indices.size(),3):
					var a:=vertices[indices[i]];var b:=vertices[indices[i+1]];var c:=vertices[indices[i+2]]
					valid=valid and (b-a).cross(c-a).length_squared()>=1e-12;triangles+=1
		check(valid and triangles>0,"joined roof/gable planes have no collision slivers at chunk boundaries, pose "+str(pose))
	var comparison_points:=PackedVector3Array()
	for x in 8:
		for y in 8:
			for z in 8:comparison_points.append(Vector3(x+.5,y+.5,z+.5)/8)
	for pair in [[4,3,35,0],[4,1,35,2],[4,0,35,1],[4,2,35,3],[12,0,36,0],[12,1,36,1],[12,2,36,2],[12,3,36,3]]:
		blocks.restore_snapshot(empty);blocks.set_cells(PackedInt32Array([0,0,0,blocks.encode_block(pair[0],pair[1],1)]))
		var old_solid:PackedByteArray=blocks.sample_solid(comparison_points)
		blocks.set_cells(PackedInt32Array([0,0,0,blocks.encode_block(pair[2],pair[3],1,4)]))
		check(old_solid==blocks.sample_solid(comparison_points),"new closed gable keeps the approved legacy solid profile "+str(pair))
	for shape in [15,17,19,20,22,24,25,26,27,32,33,34,35,36]:
		blocks.restore_snapshot(empty);blocks.set_cells(PackedInt32Array([0,0,0,blocks.encode_block(shape,0,1,4)]));blocks.flush_bakes()
		var layers:={};var mesh_count:=0
		for child in blocks.get_children():
			if child is MeshInstance3D:
				mesh_count+=1
				var arrays:Array=child.mesh.surface_get_arrays(0)
				for uv:Vector2 in arrays[Mesh.ARRAY_TEX_UV2]:layers[int(uv.x)]=true
		check(mesh_count==1 and layers.has(8) and layers.has(7) and layers.size()==2,"roof %d shares one mesh for slate above and timber underside/end"%shape)
	var records:=PackedInt32Array()
	blocks.restore_snapshot(empty)
	blocks.set_cells(PackedInt32Array([0,0,0,blocks.encode_block(31,0,2,7),0,0,1,blocks.encode_block(30,0,2,7),0,0,2,blocks.encode_block(30,0,2,7),1,0,0,blocks.encode_block(30,1,2,7)]))
	for direction in 3:
		var probes:=PackedVector3Array()
		for across in 32:
			for height in 16:
				var u:=(across+.5)/32.0;var y:=(height+.5)/128.0
				if direction==0:probes.append_array(PackedVector3Array([Vector3(u,y,.9999),Vector3(u,y,1.5)]))
				elif direction==1:probes.append_array(PackedVector3Array([Vector3(.9999,y,u),Vector3(1.5,y,u)]))
				else:probes.append_array(PackedVector3Array([Vector3(u,y,1.5),Vector3(u,y,1.9999)]))
		var samples:PackedByteArray=blocks.sample_solid(probes);var continuous:=samples.count(1)>128
		for i in range(0,samples.size(),2):continuous=continuous and samples[i]==samples[i+1]
		check(continuous,"coping seated at cell base has continuous corner/run cross-section "+str(direction))
	# A roof's texture rows must be level across its slope, and image +V must
	# point downhill. Derive gradients from the published mesh, independently
	# of the native projection implementation, including tipped/rolled mounts.
	for shape in [4,12,13,14,15,17,19,20,22,24,25,26,27,32,33,34,35,36]:
		var uv_ok:=true;var sampled:=0
		for rotation in Catalog.rotation_count(shape):
			blocks.restore_snapshot(empty);blocks.set_cells(PackedInt32Array([0,0,0,blocks.encode_block(shape,rotation,1,4)]));blocks.flush_bakes()
			var basis:Basis=blocks.shape_orientation(rotation)
			for child in blocks.get_children():
				if not child is MeshInstance3D:continue
				var arrays:Array=child.mesh.surface_get_arrays(0)
				var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
				var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV];var layers:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
				for i in range(0,indices.size(),3):
					var a:=indices[i];var b:=indices[i+1];var c:=indices[i+2];var normal:=basis.inverse()*normals[a]
					if int(layers[a].x)!=8 or normal.y<=.01 or normal.y>.999:continue
					var e:=basis.inverse()*(points[b]-points[a]);var f:=basis.inverse()*(points[c]-points[a]);var du:=uv[b]-uv[a];var dv:=uv[c]-uv[a]
					var determinant:=e.length_squared()*f.length_squared()-pow(e.dot(f),2)
					if determinant<1e-12:continue
					var gu:Vector3=(e*(du.x*f.length_squared()-dv.x*e.dot(f))+f*(dv.x*e.length_squared()-du.x*e.dot(f)))/determinant
					var gv:Vector3=(e*(du.y*f.length_squared()-dv.y*e.dot(f))+f*(dv.y*e.length_squared()-du.y*e.dot(f)))/determinant
					var downhill:=Vector3.DOWN+normal*normal.y
					uv_ok=uv_ok and absf(gu.dot(downhill))<.0001 and gv.dot(downhill)>.0001;sampled+=1
		check(uv_ok and sampled>0,"roof %d published UV courses are level and drain downhill through every mount"%shape)
	for appearance in 8:
		for material in 4:records.append_array(PackedInt32Array([appearance,0,material,blocks.encode_block(19+appearance,material,material,appearance)]))
	blocks.restore_snapshot(empty);blocks.set_cells(records)
	var saved:PackedByteArray=blocks.capture_snapshot()
	check(saved.decode_u32(4)==3 and blocks.restore_snapshot(saved) and blocks.capture_snapshot()==saved,"appearance snapshot uses version 3 and restores exact bytes")
	var malformed:=saved.duplicate();malformed.encode_u32(4,2)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(malformed.slice(0,-32));var digest:=hash.finish()
	for i in 32:malformed[malformed.size()-32+i]=digest[i]
	check(not blocks.restore_snapshot(malformed) and blocks.capture_snapshot()==saved,"version downgrade with valid checksum rejects atomically")
	var packet:PackedByteArray=blocks.capture_region(Vector3i.ZERO)
	check(blocks.validate_region_snapshot(packet) and blocks.unload_region(packet) and blocks.restore_region(packet,PackedByteArray()) and blocks.capture_snapshot()==saved,"region paging preserves appearances")
	var prefab:Resource=ClassDB.instantiate("NativeBlockPrefab");prefab.configure(records)
	check(prefab.get_material_counts()==PackedInt64Array([8,8,8,8]),"prefab crafting counts use structural materials across eight finishes")
	blocks.restore_snapshot(empty);check(blocks.place_prefab(prefab,Vector3i.ZERO,1),"appearance prefab supports native yaw")
	var rotate_ok:=true
	for offset in range(0,records.size(),4):
		var p:=Vector3i(-records[offset+2],0,records[offset]);var original:Dictionary=blocks.decode_block(records[offset+3]);var word:int=blocks.get_cell(p)
		rotate_ok=rotate_ok and word==blocks.encode_block(original.shape,(original.rotation+1)%4,original.material,original.appearance)
	check(rotate_ok,"prefab rotation retains each appearance and structural material")
	blocks.restore_snapshot(saved);blocks.configure_history(1048576,32)
	check(blocks.set_cells(PackedInt32Array([0,0,0,0])) and blocks.get_cell(Vector3i(1,0,0))==records[16+3] and blocks.undo() and blocks.capture_snapshot()==saved,"one-cell removal and undo preserve adjacent appearance cells")
	blocks.flush_bakes()
	check(blocks.stats().appearance_layers==8,"shared appearance array loaded for published geometry")
	var file:=FileAccess.open("user://building_expansion_roundtrip.bin",FileAccess.WRITE);file.store_buffer(saved);file.close()
	blocks.free();print("BUILDING_EXPANSION checks=",checks," failures=",failures);quit(1 if failures else 0)
