# SPDX-License-Identifier: 0BSD
extends "res://tests/exploration_layouts.gd"
var folder:="res://reports/exploration_review"
var stage:Node3D
var camera:Camera3D
var host:Node3D
var tick_host:=false
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):folder=argument.trim_prefix("--review-output=")
	run.call_deferred()
func run()->void:
	DirAccess.make_dir_recursive_absolute(folder)
	core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,29]))
	var layouts:=Layouts.load_catalog();var planned:Dictionary=core.plan_exploration_sites(layouts,[],[])
	check(planned.get("ok",false) and planned.get("sites",[]).size()==2,"natural seed-1703 locations available for review")
	if failures:quit(1);return
	FileAccess.open(folder.path_join("sites.json"),FileAccess.WRITE).store_string(JSON.stringify(planned,"\t"))
	physics_frame.connect(func():
		if tick_host:host.update(1./60.,camera.global_position,true))
	for site:Dictionary in planned.sites:
		var layout:Dictionary=layouts.filter(func(value:Dictionary):return value.id==site.id)[0]
		var cuts:=Layouts.segments(layout,site.origin,site.rotation);cuts.push_front(site.approach)
		for packet:PackedByteArray in Earthworks.packets(cuts):
			if not Codec.reply_ok(core.execute(packet)):check(false,"native cave cut failed");quit(1);return
		stage=Node3D.new();root.add_child(stage)
		var material:=preload("res://addons/volumetric_terrain/runtime_assets.gd").make_terrain_material()
		material.set_shader_parameter("surrounding_coast",true);material.set_shader_parameter("regional_temperate",true);material.set_shader_parameter("alpine_snow_enabled",true)
		var bounds:AABB=site.bounds.grow(20)
		for row in range(floori(bounds.position.z/16)*16,ceili(bounds.end.z/16)*16,16):
			for column in range(floori(bounds.position.x/16)*16,ceili(bounds.end.x/16)*16,16):
				var packet:PackedByteArray=core.execute(Codec.command(1,[column,row,16,1]));var decoded:=Codec.decode_mesh(packet.slice(16))
				if decoded.has("error"):check(false,"native review mesh");quit(1);return
				if decoded.triangles==0:continue
				var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,decoded.arrays)
				var view:=MeshInstance3D.new();view.mesh=mesh;view.material_override=material;stage.add_child(view)
				var body:=StaticBody3D.new();var collision:=CollisionShape3D.new();var shape:=ConcavePolygonShape3D.new();shape.set_faces(decoded.faces);collision.shape=shape;body.add_child(collision);stage.add_child(body)
				await process_frame
		var structures:=preload("res://addons/structures/structures_world.gd").new();stage.add_child(structures)
		var crate:=preload("res://addons/structures/storage_catalog.gd").register(structures)
		var asset:=Layouts.prefab(layout)
		var field:=preload("res://tests/terrain_block_contract.gd").Field.new();stage.add_child(field);field.core=core
		field.validator=preload("res://addons/structures/foundation_check.gd").new()
		field.density_revision=core.execute(Codec.command(0)).decode_u32(12)
		if asset.get_cell_count()>0:
			check(field.validator.begin(field,asset,site.origin,site.rotation),"shared timber foundation check starts")
			while field.validator.status=="checking":field.validator.tick(field);await process_frame
			check(field.validator.status=="supported","timber support and exposed surfaces: "+field.validator.status)
		check(field.validator.begin_ground_models(field,asset,site.origin,site.rotation,structures.model_collections()),"shared grounded-container check starts")
		while field.validator.status=="checking":field.validator.tick(field);await process_frame
		check(field.validator.status=="supported","container support, deep continuity and full bounds clearance: "+field.validator.status)
		var placement=ClassDB.instantiate("NativePrefabPlacement")
		var placed:Dictionary=placement.place(structures.blocks,asset,site.origin,site.rotation,structures.model_collections(),[])
		print("EXPLORATION_PREFAB ",site.id," ",placed)
		check(not crate.is_empty() and placed.get("ok",false),"grid timbers and native crate models publish: "+site.id)
		structures.blocks.set_focus(Vector3(site.origin));structures.blocks.flush_bakes();structures.set_model_focus(Vector3(site.origin))
		var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.shadow_enabled=true;stage.add_child(light)
		var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.4,.55,.6);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color(.6,.67,.75);environment.environment.ambient_light_energy=.6;stage.add_child(environment)
		camera=Camera3D.new();camera.far=400;camera.current=true;stage.add_child(camera);camera.position=Vector3(site.origin)+Vector3(0,1.7,-6)
		var lamp:=SpotLight3D.new();lamp.light_color=Color(1,.9,.74);lamp.light_energy=2;lamp.spot_range=18;lamp.spot_angle=48;lamp.shadow_enabled=true;camera.add_child(lamp)
		var target:=Node3D.new();stage.add_child(target);target.position=Vector3(site.origin)+Vector3(0,0,-200)
		host=preload("res://addons/characters/runtime/zombie_world.gd").new();host.target=target;host.enabled=true;host.population_enabled=false
		host.readiness=func(_bounds:AABB):return true
		stage.add_child(host)
		for frame in 20:await physics_frame
		tick_host=true;var residents:Array=[]
		for anchor:Dictionary in Layouts.sleepers(layout,site.origin,site.rotation):
			var zombie:CharacterBody3D=host.spawn_at(anchor.position,false,true)
			if zombie!=null:zombie.rotation.y=anchor.yaw
			check(zombie!=null and host.put_to_sleep(zombie,anchor.pose),"authored sleeper clears actual cave terrain/timbers")
			if zombie!=null:residents.append(zombie)
		for frame in 12:await physics_frame
		for index in layout.views.size():
			var view:Array=layout.views[index]
			camera.position=Vector3(site.origin)+Layouts.turn(Vector3(view[0],view[1],view[2]),site.rotation)
			check(density(camera.position)>.15,"authored review viewpoint stays outside terrain")
			camera.look_at(Vector3(site.origin)+Layouts.turn(Vector3(view[3],view[4],view[5]),site.rotation));lamp.visible=index>0
			for frame in 12:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join(site.id+"_"+str(index)+".png"))
			if index==0:
				var diagnostic:=ShaderMaterial.new();diagnostic.shader=Shader.new()
				diagnostic.shader.code="shader_type spatial; render_mode unshaded; varying vec3 surface_normal; void vertex(){surface_normal=MODEL_NORMAL_MATRIX*NORMAL;} void fragment(){ALBEDO=vec3(.55)+surface_normal*.35;}"
				for child:Node in stage.get_children():
					if child is MeshInstance3D:child.material_override=diagnostic
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder.path_join(site.id+"_entrance_geometry.png"))
				for child:Node in stage.get_children():
					if child is MeshInstance3D:child.material_override=material
		for zombie:CharacterBody3D in residents:host.hear_noise(zombie.global_position,5.)
		for frame in 300:await physics_frame
		for zombie:CharacterBody3D in residents:check(not zombie.sleeper_active(),"living sleeper completes wake against real cave collision")
		tick_host=false;stage.queue_free();await process_frame
	print("EXPLORATION_REVIEW checks=",checks," failures=",failures)
	quit(1 if failures else 0)
