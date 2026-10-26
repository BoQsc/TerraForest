extends "res://tests/terrain_worker_publication_probe.gd"

func run()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var native:RefCounted=ClassDB.instantiate("TerrainCore")
	var results:Array=[]
	for generator:int in [1,23]:
		check(Codec.reply_ok(native.execute(Codec.command(6,[1703,generator]))),"native column fixture generator %d"%generator)
		for site:Vector2i in [Vector2i(1280,1248),Vector2i(960,960),Vector2i(0,0),Vector2i(1984,1984)]:
			for edited:bool in [false,true]:
				if edited:
					var point:=Vector3(site.x+16,0,site.y+16)
					point.y=native.execute(Codec.point_command(point)).decode_float(12)
					check(Codec.reply_ok(native.execute(Codec.brush(point,point,4,0,false,1))),"seam excavation admitted")
				var epoch:int=native.execute(Codec.command(13)).decode_u32(12)
				var before:PackedByteArray=native.execute(Codec.command(4))
				var fine:PackedByteArray=native.build_owned_column(site.x,site.y,32,1,epoch)
				var original:PackedByteArray=native.execute(Codec.command(1,[site.x,site.y,32,1,epoch])).slice(16)
				check(not fine.is_empty() and triangle_multiset([fine])==triangle_multiset([original]),"column and ordinary fine mesh have identical oriented surfaces and normals")
				for step:int in [2,4,8]:
					var started:=Time.get_ticks_usec()
					var column:PackedByteArray=native.build_owned_column(site.x,site.y,32,step,epoch)
					var elapsed:float=(Time.get_ticks_usec()-started)/1000.0
					var slabs:Array=[]
					for bottom:int in range(0,256,32):slabs.append(native.build_owned_region(site.x,site.y,32,step,bottom,bottom+32,epoch))
					check(not column.is_empty() and triangle_multiset([column])==triangle_multiset(slabs),"coarse full column matches all eight owned slabs")
					if site.x<1984:
						var neighbours:Array=[]
						for offset:int in [0,16]:neighbours.append(native.execute(Codec.command(1,[site.x+32,site.y+offset,16,1,epoch])).slice(16))
						var boundary:Dictionary=boundary_edges([column],0,site.x+32)
						check(not boundary.is_empty() and boundary==boundary_edges(neighbours,0,site.x+32),"coarse column joins ordinary fine terrain exactly")
					results.append({"generator":generator,"site":str(site),"edited":edited,"step":step,"worker_ms":elapsed,"bytes":column.size()})
				check(before==native.execute(Codec.command(4)),"derived column builds preserve authoritative saved world bytes")
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
