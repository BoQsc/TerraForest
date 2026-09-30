extends SceneTree
var checks: Array[Dictionary]=[]
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks.append({"passed":value,"name":label});print("PASS " if value else "FAIL ",label)
func area(packet: PackedByteArray) -> float:
	var count:=int(packet.decode_u32(24));var total:=0.0
	var points:=packet.slice(36,36+count*12).to_vector3_array()
	var offset:=36+count*56
	for i in range(0,packet.decode_u32(28),3):
		var a:=points[packet.decode_u32(offset+i*4)];var b:=points[packet.decode_u32(offset+(i+1)*4)];var c:=points[packet.decode_u32(offset+(i+2)*4)]
		total+=(b-a).cross(c-a).length()*0.5
	return total
func seam_edges(packets: Array,axis: int,plane: float) -> Dictionary:
	var edges: Dictionary={}
	for packet: PackedByteArray in packets:
		var count:=int(packet.decode_u32(24));var points:=packet.slice(36,36+count*12).to_vector3_array();var offset:=36+count*56
		for i in range(0,packet.decode_u32(28),3):
			var triangle: Array[Vector3]=[]
			for j in range(3): triangle.append(points[packet.decode_u32(offset+(i+j)*4)])
			if triangle.all(func(p: Vector3): return p[axis]==plane): continue
			for j in range(3):
				var a:=triangle[j];var b:=triangle[(j+1)%3]
				if a[axis]!=plane or b[axis]!=plane or a==b: continue
				var keys: Array[String]=[PackedVector3Array([a]).to_byte_array().hex_encode(),PackedVector3Array([b]).to_byte_array().hex_encode()];keys.sort()
				var key:=keys[0]+keys[1];edges[key]=int(edges.get(key,0))+1
	return edges
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var native=ClassDB.instantiate("TerrainCore")
	var points:=PackedVector3Array([Vector3(0,20,0),Vector3(256,40,0),Vector3(256,40,256),Vector3(0,20,256),Vector3(128,20,20),Vector3(128,60,20),Vector3(128,20,60)])
	var normals:=PackedVector3Array();var uv:=PackedVector2Array();var uv2:=PackedVector2Array();var colors:=PackedColorArray()
	for p in points:
		normals.append(Vector3.UP);uv.append(Vector2(p.x/256,p.z/256));uv2.append(Vector2(0,8));colors.append(Color(p.x/256,p.z/256,0,1))
	var packet:=PackedByteArray();packet.resize(36)
	var header:=[0x324d5254,5,0,0,256,8,points.size(),9,0]
	for i in range(9): packet.encode_u32(i*4,header[i])
	for channel in [points.to_byte_array(),normals.to_byte_array(),uv.to_byte_array(),uv2.to_byte_array(),colors.to_byte_array(),PackedInt32Array([0,2,1,0,3,2,4,5,6]).to_byte_array()]: packet.append_array(channel)
	var begin:=Time.get_ticks_usec();var children: Array=native.experimental_partition_mesh(packet);var elapsed:=(Time.get_ticks_usec()-begin)/1000.0
	check(children.size()==4,"four children produced")
	var sum:=0.0;var attributes:=true;var ownership:=true;var wall_triangles:=0
	for child in range(children.size()):
		var data: PackedByteArray=children[child];sum+=area(data)
		var count:=int(data.decode_u32(24));var p:=data.slice(36,36+count*12).to_vector3_array()
		for i in range(count):
			ownership=ownership and (p[i].x>=128 if child&1 else p[i].x<=128) and (p[i].z>=128 if child&2 else p[i].z<=128)
			var at:=36+count*24+i*8
			attributes=attributes and abs(data.decode_float(at)-p[i].x/256)<0.000001 and abs(data.decode_float(at+4)-p[i].z/256)<0.000001
		var offset:=36+count*56
		for i in range(0,data.decode_u32(28),3):
			var a:=p[data.decode_u32(offset+i*4)];var b:=p[data.decode_u32(offset+(i+1)*4)];var c:=p[data.decode_u32(offset+(i+2)*4)]
			if a.x==128 and b.x==128 and c.x==128:
				wall_triangles+=1;ownership=ownership and child==1
	check(abs(sum-area(packet))<0.02,"surface area retained without duplicate coplanar wall")
	check(ownership and wall_triangles==1,"split-plane wall has exactly one owner")
	check(attributes,"interpolated lighting channels follow original surface")
	check(seam_edges([children[0],children[2]],0,128)==seam_edges([children[1],children[3]],0,128),"synthetic X seam edges match bit for bit")
	check(seam_edges([children[0],children[1]],2,128)==seam_edges([children[2],children[3]],2,128),"synthetic Z seam edges match bit for bit")
	var grandchildren_area:=0.0
	for child: PackedByteArray in children:
		for grandchild: PackedByteArray in native.experimental_partition_mesh(child): grandchildren_area+=area(grandchild)
	check(abs(grandchildren_area-area(packet))<0.03,"recursive partition retains surface area")
	var real_fixtures: Array[Dictionary]=[]
	for origin in [Vector2i(1280,1280),Vector2i(768,768)]:
		var request:=PackedByteArray();request.resize(20)
		for i in range(5): request.encode_u32(i*4,[1,origin.x,origin.y,256,8][i])
		var reply: PackedByteArray=native.execute(request)
		var original:=reply.slice(16);begin=Time.get_ticks_usec()
		var parts: Array=native.experimental_partition_mesh(original)
		var partition_ms:=(Time.get_ticks_usec()-begin)/1000.0
		var total_area:=0.0;var total_bytes:=0;var total_vertices:=0
		for part: PackedByteArray in parts:
			total_area+=area(part);total_bytes+=part.size();total_vertices+=int(part.decode_u32(24))
		check(parts.size()==4 and abs(total_area-area(original))<maxf(0.1,area(original)*0.000001),"real terrain partition preserves area "+str(origin))
		check(total_vertices<int(original.decode_u32(24))*1.5,"real terrain retains indexed interior vertices "+str(origin))
		check(seam_edges([parts[0],parts[2]],0,origin.x+128)==seam_edges([parts[1],parts[3]],0,origin.x+128),"real terrain X seam edges match bit for bit "+str(origin))
		check(seam_edges([parts[0],parts[1]],2,origin.y+128)==seam_edges([parts[2],parts[3]],2,origin.y+128),"real terrain Z seam edges match bit for bit "+str(origin))
		real_fixtures.append({"origin":str(origin),"partition_ms":partition_ms,"source_bytes":original.size(),"partition_bytes":total_bytes})
	for fault in ["truncated","nan","index","unaligned"]:
		var bad:=packet.duplicate()
		if fault=="truncated": bad.resize(bad.size()-1)
		elif fault=="nan": bad.encode_float(36,NAN)
		elif fault=="index": bad.encode_u32(36+points.size()*56,999)
		elif fault=="unaligned": bad.encode_u32(8,1)
		check(native.experimental_partition_mesh(bad).is_empty(),"reject "+fault)
	var failures:=0
	for row in checks:
		if not row.passed: failures+=1
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/command.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"partition_ms":elapsed,"real_fixtures":real_fixtures},"  "));file.close();native=null
	quit(0 if failures==0 else 1)
