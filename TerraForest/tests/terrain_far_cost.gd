extends SceneTree

const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const SAVE="user://worlds/recipe_generated_4644d8cfc8f97e43.trw"

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var archive:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var original:PackedByteArray=archive.read(ProjectSettings.globalize_path(SAVE))
	var decoded:Dictionary=archive.decode(original)
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	if not decoded.get("ok",false) or not core.mount_storage_checkpoint(ProjectSettings.globalize_path(SAVE)+".terrain",decoded.sections.terrain):quit(1);return
	core.execute(Codec.command(18,[1]))
	var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
	var rows:=[]
	for site:Vector2i in [Vector2i(1024,1280),Vector2i(0,0),Vector2i(512,512)]:
		for mode:String in ["columns32","columns64","whole"]:
			var started:=Time.get_ticks_usec()
			var stages:=[0.0,0.0,0.0,0.0]
			var triangles:=0
			var bytes:=0
			var size:=32 if mode=="columns32" else 64
			var count:=256/size if mode!="whole" else 1
			for along in count:
				for across in count:
					var packet:PackedByteArray=core.build_owned_column(site.x+across*size,site.y+along*size,size,8,epoch) if mode!="whole" else core.execute(Codec.command(1,[site.x,site.y,256,8,epoch])).slice(16)
					var timings:PackedByteArray=core.execute(Codec.command(19))
					if packet.size()<36:quit(1);return
					for index in 4:stages[index]+=timings.decode_float(12+index*4)
					triangles+=packet.decode_u32(28)/3
					bytes+=packet.size()
			var row:={"site":str(site),"mode":mode,"stages":stages,"ms":(Time.get_ticks_usec()-started)/1000.0,"triangles":triangles,"bytes":bytes}
			rows.append(row);print(JSON.stringify(row))
	FileAccess.open("res://reports/terrain_far_cost.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
	var unchanged:bool=archive.read(ProjectSettings.globalize_path(SAVE))==original
	print("TERRAIN_FAR_COST failures=",0 if unchanged else 1)
	quit(0 if unchanged else 1)
