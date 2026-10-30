extends "res://tests/terrain_worker_publication_probe.gd"

func run()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var native:RefCounted=ClassDB.instantiate("TerrainCore")
	var results:Array=[]
	for generator:int in [1,23]:
		check(Codec.reply_ok(native.execute(Codec.command(6,[1703,generator]))),"native column fixture generator %d"%generator)
		for fixture:Array in [[Vector2i(1280,1248),32],[Vector2i(960,960),32],[Vector2i(0,0),32],[Vector2i(1984,1984),32],[Vector2i(1280,1216),64],[Vector2i(960,960),64],[Vector2i(0,0),64],[Vector2i(1984,1984),64]]:
			var site:Vector2i=fixture[0]
			var size:int=fixture[1]
			for edited:bool in [false,true]:
				if edited:
					var point:=Vector3(mini(site.x+size/2,1992),0,mini(site.y+size/2,1992))
					point.y=native.execute(Codec.point_command(point)).decode_float(12)
					check(Codec.reply_ok(native.execute(Codec.brush(point,point,4,0,false,1))),"seam excavation admitted")
				var epoch:int=native.execute(Codec.command(13)).decode_u32(12)
				var before:PackedByteArray=native.execute(Codec.command(4))
				var fine:PackedByteArray=native.build_owned_column(site.x,site.y,size,1,epoch)
				var original:PackedByteArray=native.execute(Codec.command(1,[site.x,site.y,size,1,epoch])).slice(16)
				check(not fine.is_empty() and triangle_multiset([fine])==triangle_multiset([original]),"column and ordinary fine mesh have identical oriented surfaces and normals")
				for step:int in [2,4,8]:
					var started:=Time.get_ticks_usec()
					var column:PackedByteArray=native.build_owned_column(site.x,site.y,size,step,epoch)
					var elapsed:float=(Time.get_ticks_usec()-started)/1000.0
					var whole:PackedByteArray=native.execute(Codec.command(1,[site.x,site.y,size,step,epoch])).slice(16)
					check(not column.is_empty() and triangle_multiset([column])==triangle_multiset([whole]),"coarse column matches whole-owner volumetric simplification")
					if site.x<1984:
						for axis:int in [0,2]:
							var neighbours:Array=[]
							for offset:int in range(0,size,16):
								neighbours.append(native.execute(Codec.command(1,[site.x+(size if axis==0 else offset),site.y+(offset if axis==0 else size),16,1,epoch])).slice(16))
							var plane:int=(site.x if axis==0 else site.y)+size
							var span:int=site.y if axis==0 else site.x
							var boundary:Dictionary=join_edges([column],axis,plane,span,span+size)
							var other:Dictionary=join_edges(neighbours,axis,plane,span,span+size)
							check(not boundary.is_empty() and boundary==other,"coarse column joins ordinary fine terrain exactly in axis %d"%axis)
							check(boundary_edges([column],axis,plane)==boundary_edges([fine],axis,plane),"complete column edge including corner matches fine owner")
					results.append({"generator":generator,"site":str(site),"size":size,"edited":edited,"step":step,"worker_ms":elapsed,"bytes":column.size()})
				check(before==native.execute(Codec.command(4)),"derived column builds preserve authoritative saved world bytes")
		verify_mixed_corner(native)
	var epoch:int=native.execute(Codec.command(13)).decode_u32(12)
	check(native.build_owned_column(1,0,32,8,epoch).is_empty(),"misaligned owner rejected")
	check(native.build_owned_column(0,0,128,8,epoch).is_empty(),"whole-root reconstruction cannot enter bounded column API")
	check(native.build_owned_column(0,0,32,3,epoch).is_empty(),"invalid LOD rejected")
	native.execute(Codec.command(12))
	check(native.build_owned_column(0,0,32,8,epoch).is_empty(),"cancelled build cannot publish stale column")
	var folder:=ProjectSettings.globalize_path("res://reports")
	DirAccess.make_dir_recursive_absolute(folder)
	var file:=FileAccess.open(folder.path_join("terrain_local_columns.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"results":results},"  "));file.close()
	print("TERRAIN_LOCAL_COLUMNS failures=",failures)
	quit(1 if failures else 0)

func join_edges(packets:Array,axis:int,plane:float,start:int,end:int)->Dictionary:
	var result:Dictionary={}
	var along:int=2 if axis==0 else 0
	for edge:String in boundary_edges(packets,axis,plane):
		var positions:PackedFloat32Array=edge.hex_decode().to_float32_array()
		if positions[along]>=start and positions[along]<end-1 and positions[along+3]>=start and positions[along+3]<end-1:result[edge]=true
	return result

func verify_mixed_corner(native:Object)->void:
	var epoch:int=native.execute(Codec.command(13)).decode_u32(12)
	var coarse:=[]
	var fine:=[]
	for along:int in 2:
		for across:int in 2:
			var step:int=8 if along==0 and across==0 else (4 if along==1 and across==1 else 1)
			coarse.append(native.build_owned_column(960+64*across,960+64*along,64,step,epoch))
			fine.append(native.build_owned_column(960+64*across,960+64*along,64,1,epoch))
	check(open_edges(coarse)==open_edges(fine),"four mixed-LOD columns add no cracks at their shared corner or cave joins")

func open_edges(packets:Array)->Dictionary:
	var counts:Dictionary={}
	for packet:PackedByteArray in packets:
		var decoded:Dictionary=Codec.decode_mesh(packet)
		var positions:PackedVector3Array=decoded.arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=decoded.arrays[Mesh.ARRAY_INDEX]
		for at:int in range(0,indices.size(),3):
			for side:int in 3:
				var first:String=PackedVector3Array([positions[indices[at+side]]]).to_byte_array().hex_encode()
				var second:String=PackedVector3Array([positions[indices[at+(side+1)%3]]]).to_byte_array().hex_encode()
				var edge:String=first+second if first<second else second+first
				counts[edge]=int(counts.get(edge,0))+1
	var result:Dictionary={}
	for edge:String in counts:
		if counts[edge]!=2:result[edge]=counts[edge]
	return result
