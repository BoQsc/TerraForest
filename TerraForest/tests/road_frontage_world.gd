extends "res://tests/combined_resource_route.gd"
var review:Node
var view:=SubViewport.new()
var results:Dictionary={}
func _process(_delta:float)->bool:
	if is_instance_valid(review) and is_instance_valid(review.game):review.game.app_focused=true
	return false
func surface_height(across:float,depth:float)->float:
	for road:Dictionary in review.current.roads:
		if absf(road.start.z-depth)>.001 or absf(road.finish.z-depth)>.001 or road.finish.x-road.start.x<2 or across<road.start.x or across>road.finish.x:continue
		var fraction:float=(across-road.start.x)/(road.finish.x-road.start.x)
		var index:int=road.curve_index*4
		return ((road.coefficients[index]*fraction+road.coefficients[index+1])*fraction+road.coefficients[index+2])*fraction+road.coefficients[index+3]
	return NAN
func aim_road(point:Vector3)->Dictionary:
	game.player.position=point+Vector3(0,0,3)
	game.camera.global_position=point+Vector3(0,1.8,2.8);game.camera.look_at(point-Vector3(0,.5,0))
	return game._structure_target(false)
func capture(name:String,focus:Vector3,overview:bool=false)->void:
	game.camera.global_position=focus+(Vector3(-16,21,25) if overview else Vector3(4,2.4,6))
	game.camera.look_at(focus+Vector3(0,.3,0))
	game.structures.blocks.flush_bakes()
	for frame in 60:await process_frame
	game.set_process(false);game.shape_preview.hide();game.prefab_preview.hide()
	check(not game.loading_active and not game.loading_layer.visible,"visible gameplay for "+name)
	await RenderingServer.frame_post_draw
	check(view.get_texture().get_image().save_png(evidence.path_join(name+".png"))==OK,"captured "+name)
	game.set_process(true)
func survey()->Array:
	var rows:Array=[]
	var center:Vector3=review.current.center
	for depth in [center.z-24,center.z+24]:
		for beginning in range(int(center.x)-52,int(center.x)+52,16):
			var anchor:=Vector3(beginning+8,surface_height(beginning+8,depth),depth)
			game.teleport(anchor,anchor.y+.1)
			if not check(await wait_for(func():return not game.loading_active and game._placement_collision_ready(AABB(anchor-Vector3(10,3,4),Vector3(20,7,8))),45),"road sample group is resident"):return []
			game.needs_floor_spawn=false
			for across in range(beginning,mini(beginning+16,int(center.x)+52)):
				var height:=surface_height(across+.5,depth)
				for lateral in [-2,0,2]:
					var point:=Vector3(across+.5,height,depth+lateral+.5)
					var cell:=Vector3i(across,floori(height),int(depth)+lateral)
					var fit:Dictionary=game.structures.blocks.placement_support(AABB(Vector3(cell),Vector3.ONE),point,true,true,[game.player.get_rid()])
					rows.append({"cell":cell,"frontage":across>=center.x-26 and across<center.x+26,"support":fit})
	return rows
func summarize(rows:Array,frontage:bool)->Dictionary:
	var summary:={"samples":0,"close":0,"over_50cm":0,"worst_gap":0.0,"max_burial":0.0,"complete":true}
	for row:Dictionary in rows:
		if frontage and not row.frontage:continue
		var fit:Dictionary=row.support
		summary.samples+=1
		if not fit.get("ok",false) or fit.hits!=9:summary.complete=false;continue
		summary.close+=int(fit.gap<=.15);summary.over_50cm+=int(fit.gap>.5)
		summary.worst_gap=maxf(summary.worst_gap,fit.gap);summary.max_burial=maxf(summary.max_burial,fit.maximum-fit.bottom)
	return summary
func run()->void:
	evidence="res://reports/road_frontage_review";DirAccess.make_dir_recursive_absolute(evidence)
	view.size=Vector2i(1920,1080);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	review=load("res://reviews/roads/frontage_review.tscn").instantiate();review.automatic=false;view.add_child(review)
	if not check(await review.prepare(),"native roads, terrain and approved buildings generated together"):await finish();return
	for enabled in [true,false]:
		if not enabled and not check(await review.show_variant(false),"baseline regenerates in the same viewport"):await finish();return
		game=review.game;game.set_physics_process(false);game._clear_motion()
		var label:="proposed" if enabled else "baseline"
		var rows:=await survey()
		var frontage:=summarize(rows,true);var complete:=summarize(rows,false)
		check(rows.size()==624 and complete.complete,"both full road corridors have complete native collision coverage")
		if enabled:check(frontage.samples==312 and frontage.close==312 and frontage.max_burial<=.201,"all 312 frontage footprints keep close contact without deep burial")
		results[label]={"frontage":frontage,"whole_roads":complete,"rows":rows}
		print("CONTACT ",label," frontage=",frontage," whole_roads=",complete)
		await review.visit(0);game.set_physics_process(false);game.needs_floor_spawn=false
		var center:Vector3=review.current.center
		var point:=Vector3(center.x+6.5,surface_height(center.x+6.5,center.z-24),center.z-23.5)
		var target:=aim_road(point)
		if not check(target.get("placement_ok",false),"normal targeting accepts "+label+" sample"):await finish();return
		var revision:int=game.terrain.density_revision
		game._edit_structure(false)
		check(game.structures.blocks.get_cell(target.target)==1,"normal click places exactly one brick on the unchanged grid")
		check(game.terrain.density_revision==revision and game.structures.blocks.get_cell(target.target-Vector3i.UP)==0,"placing a brick adds neither support blocks nor terrain edits")
		await capture(label,Vector3(target.target)+Vector3.ONE*.5)
		await capture(label+"_overview",Vector3(center.x,point.y,center.z),true)
		game.structures.blocks.set_cells(PackedInt32Array([target.target.x,target.target.y,target.target.z,0]))
		var floating:=Vector3i(int(center.x)+6,50,int(center.z)-24)
		game.structures.blocks.set_cells(PackedInt32Array([floating.x,floating.y,floating.z,1]));game.structures.blocks.flush_bakes()
		await wait_for(func():return game._placement_collision_ready(AABB(Vector3(floating),Vector3.ONE*2)),10)
		game.camera.global_position=Vector3(floating)+Vector3(.5,.5,3);game.camera.look_at(Vector3(floating)+Vector3.ONE*.5)
		var airborne:Dictionary=game._structure_target(false)
		check(airborne.get("placement_ok",false) and airborne.target==floating+Vector3i(0,0,1),"intentional floating attachment remains allowed")
	check(results.proposed.frontage.close>results.baseline.frontage.close,"frontage contact improves over locally rounded nodes")
	FileAccess.open(evidence.path_join("contact.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	await finish()
func finish()->void:
	if is_instance_valid(review):
		if is_instance_valid(review.game):
			review.game.shutdown_requested=true
			check(await review.game.terrain.shutdown_after_edits(),"temporary comparison closes without saving")
		review.free();game=null;await process_frame
	print("ROAD_FRONTAGE_WORLD failures=",failures)
	quit(1 if failures else 0)
