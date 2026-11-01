# SPDX-License-Identifier: 0BSD
extends SceneTree
const Recipe=preload("res://reviews/building_expansion/recipes.gd")
const NAMES=["Shallow roof","Hip corner","Valley corner","Cornice","Closed gable"]
func _initialize()->void:run.call_deferred()
func run()->void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(512,320);viewport.transparent_bg=true;viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_4X;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7;viewport.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-35,0);sun.light_energy=1.4;viewport.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;viewport.add_child(camera);camera.current=true
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");viewport.add_child(blocks);blocks.set_process(false)
	var empty:PackedByteArray=blocks.capture_snapshot();var atlas:=Image.create(256*5,160,false,Image.FORMAT_RGBA8);atlas.fill(Color.TRANSPARENT)
	var receipt:={"license":"CC0-1.0","source":"Original native cell assemblies in tools/bake_building_assemblies.gd","assemblies":[]}
	for index in 5:
		blocks.restore_snapshot(empty);var cells:={}
		if index in [0,4]:
			for z in range(1 if index==4 else 4):
				for spec in [[0,0,19,0],[1,0,20,0],[2,1,22,0],[3,0,20,2],[4,0,19,2],[0,-1,21,0],[2,0,23,0],[4,-1,21,2]]:
					var shape:int=spec[2]
					if index==4:shape={19:32,20:33,22:34}.get(shape,shape)
					cells[Vector3i(spec[0],spec[1],z)]=blocks.encode_block(shape,spec[3],1,4)
		elif index in [1,2]:
			Recipe.hip_canopy(blocks,cells,Rect2i(0,0,4,4),0)
			if index==2:
				cells.clear()
				for x in 2:
					for z in 2:
						cells[Vector3i(x,0,z)]=blocks.encode_block(26+x if x==z else 20,0 if x>=z else 1,1,4)
		else:Recipe.crown(blocks,cells,Rect2i(0,0,2,2),0)
		var records:=PackedInt32Array();var bounds:=AABB()
		for cell:Vector3i in cells:
			records.append_array(PackedInt32Array([cell.x,cell.y,cell.z,cells[cell]]));bounds=bounds.expand(Vector3(cell)).expand(Vector3(cell)+Vector3.ONE)
		blocks.set_cells(records);blocks.flush_bakes()
		var center:=bounds.get_center();camera.position=center+Vector3(1.3,1.2,2).normalized()*12;camera.look_at(center);camera.size=bounds.size.length()*.88
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		for frame in 3:await RenderingServer.frame_post_draw
		var pixels:=viewport.get_texture().get_image();pixels.resize(256,160,Image.INTERPOLATE_LANCZOS);atlas.blit_rect(pixels,Rect2i(0,0,256,160),Vector2i(index*256,0))
		receipt.assemblies.append({"name":NAMES[index],"records":Array(records)})
	var path:="res://addons/player_runtime/art/building_assemblies.trtex"
	if atlas.save_png(path)!=OK:quit(1);return
	receipt["sha256"]=FileAccess.get_sha256(path)
	FileAccess.open("res://addons/player_runtime/art/building_assemblies.provenance.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  ")+"\n")
	viewport.free();print("BUILDING_ASSEMBLIES count=5 failures=0");quit()
