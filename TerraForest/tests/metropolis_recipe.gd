# SPDX-License-Identifier: 0BSD
extends SceneTree
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Metro=preload("res://addons/structures/metropolis_catalog.gd")
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
const Contact=preload("res://addons/structures/terrain_contact.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const GENERATOR:=33
var checks:=0
var failures:=0
var folder:=""
var seed_value:=1703
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="):folder=arg.trim_prefix("--check-evidence-dir=")
		if arg.begins_with("--seed="):seed_value=int(arg.trim_prefix("--seed="))
	run.call_deferred()
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label);return ok
func run()->void:
	if "--components-only" in OS.get_cmdline_user_args():test_components();finish();return
	if "--locate-only" in OS.get_cmdline_user_args():await locate_only();return
	var codec:=Recipe.codec();var options:=Recipe.METROPOLIS.duplicate()
	var bytes:=Recipe.encode(options)
	check(bytes.size()==44 and codec.decode(bytes)==options and codec.restore_snapshot(bytes),"durable metropolis identity and seven-community options")
	for offset in range(0,44,4):
		var corrupt:=bytes.duplicate();corrupt.encode_u32(offset,0xffffffff)
		check(not codec.restore_snapshot(corrupt) and codec.capture_snapshot()==bytes,"corrupt profile field preserves live recipe: "+str(offset))
	for legacy:Dictionary in [{"biome":0,"settlements":2,"districts":1,"network":0,"trails":1},Recipe.DEFAULTS]:
		var encoded:=Recipe.encode(legacy);check(not encoded.is_empty() and codec.decode(encoded)==legacy,"existing recipe bytes retain their original shape")
	var ids:Dictionary={};var total:=0;var light_surveys:Dictionary={}
	for block in 9:
		var lots:=Metro.recipe(Vector3(1000,0,1000),block)
		total+=lots.size()
		for lot:Dictionary in lots:
			check(Contact.describe(lot.asset).ok,"generation datum: "+lot.label)
			if not light_surveys.has(lot.asset.get_instance_id()):
				var lights:Dictionary=preload("res://addons/house_lights/generation.gd").room_plan(lot.asset)
				check(lights.get("ok",false) and not lights.get("rooms",[]).is_empty() and int(lights.get("probes",200001))<=200000,"normal bounded room-light survey: "+lot.label)
				if lights.get("pages",0)>1:
					var first:Dictionary=lot.asset.interior_light_sites()
					var second:Dictionary=lot.asset.interior_light_sites(128)
					check(not first.complete and first.rooms.size()==128 and first.next_room==128 and second.complete and first.rooms+second.rooms==lights.rooms,"room pages retain every flat without duplication: "+lot.label)
				light_surveys[lot.asset.get_instance_id()]=true
			if lot.asset.has_meta("metropolis_content_id"):ids[lot.asset.get_meta("metropolis_content_id")]=true
			if lot.asset.get_meta("grand_building_id","")=="grand_cathedral":
				var prepared:=preload("res://addons/structures/site_plan.gd").prepare(lot.asset,Vector3i(800,0,800),0,60)
				check(prepared.get("ok",false) and prepared.segments.any(func(segment:Dictionary):return segment.get("phase","")=="excavation" and segment.get("cut_only",false)),"deep cross-shaped basement has explicit final excavation")
	check(total==84,"36 city buildings and six eight-building communities")
	var root_reference:Resource=Metro.Civic.asset(1)
	var rooted:Resource=Metro.generation_asset(root_reference,"town_hall_t1")
	var root_proof=preload("res://addons/structures/foundation_geometry.gd")
	check(rooted.get_meta("metropolis_foundation_footings",0)>0 and root_proof.retains_authored_geometry(rooted,root_reference),"buried roots preserve every original room cell and attachment")
	var changed:Resource=rooted.duplicate(true);var changed_cells:PackedInt32Array=changed.get_records()
	changed_cells.append_array(PackedInt32Array([-100,0,-100,65]));changed.configure(changed_cells);changed.configure_model_attachments(rooted.get_model_attachments());changed.set_meta("metropolis_foundation_footings",int(rooted.get_meta("metropolis_foundation_footings"))+1)
	check(not root_proof.retains_authored_geometry(changed,root_reference),"unrelated extra masonry cannot reuse reviewed resident anchors")
	changed=rooted.duplicate(true);changed_cells=changed.get_records()
	var original_cell:PackedInt32Array=root_reference.get_records().slice(0,4)
	for at in range(0,changed_cells.size(),4):
		if changed_cells.slice(at,at+3)==original_cell.slice(0,3):changed_cells[at+3]=1 if original_cell[3]!=1 else 65;break
	changed.configure(changed_cells)
	changed.configure_model_attachments(rooted.get_model_attachments())
	check(not root_proof.retains_authored_geometry(changed,root_reference),"changed original room fabric cannot reuse reviewed resident anchors")
	for id:String in Metro.Grand.IDS+Metro.City.IDS+Metro.Civic.IDS+Metro.EXTRA_IDS:check(ids.has(id),"required building type: "+id)
	check(load("res://demo/worlds.gd").can_instantiate(),"ordinary browser and metropolis controls parse")
	var browser:Control=load("res://demo/worlds.tscn").instantiate();browser.preview_mode=true;root.add_child(browser)
	preload("res://demo/world_creation_panel.gd").apply_style(browser,6)
	check(browser.selected_options()==Recipe.METROPOLIS,"normal starting-recipe selection sends exact durable metropolis settings")
	check(browser.settlement_count.disabled and browser.district_count.disabled and browser.recipe_summary.text.contains("6 outlying"),"fixed metropolis layout is explicit in normal controls")
	preload("res://demo/world_creation_panel.gd").apply_style(browser,1)
	check(browser.generation_profile==0 and not browser.settlement_count.disabled and not browser.selected_options().has("profile"),"switching to an older recipe restores its own controls and settings")
	browser.free()
	var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,GENERATOR]))
	var crossing_survey:Dictionary=core.plan_lake_crossings(true)
	var spans:Array=[]
	for crossing:Dictionary in crossing_survey.get("crossings",[]):spans.append({"lake":crossing.lake_id,"kind":crossing.kind,"span":crossing.span})
	print("METROPOLIS_BRIDGE_SURVEY ",JSON.stringify(spans))
	var closest:Dictionary={}
	for row:Dictionary in crossing_survey.get("rejected",[]):
		if int(row.half_span)>14:continue
		var penalty:=maxf(0,float(row.fill)-2)+maxf(0,float(row.cut)-3)+maxf(0,float(row.slope)-.12)*20+maxf(0,.75-float(row.dry))
		if float(row.fill)<-200:penalty+=1000
		if not closest.has(row.lake_id) or penalty<closest[row.lake_id].penalty:closest[row.lake_id]={"penalty":penalty,"detail":row}
	print("METROPOLIS_SHORT_BANK_DIAGNOSTICS ",JSON.stringify(closest))
	check(crossing_survey.get("ok",false),"native bounded crossing survey completes")
	if "--site-only" in OS.get_cmdline_user_args():
		var block:=0;var hint:Vector3=Metro.HINTS[block]
		var site:Dictionary={}
		for direction in 4:
			site=Metro.Planner.locate(core,hint,[],Rect2(Vector2(128,128),Vector2(1744,1744)),Metro.mini_recipe.bind(block,0,direction),Metro.mini_streets.bind(direction),Vector2(204,204),3,true)
			if site.get("ok",false):print("METROPOLIS_ANCHOR ",site.center," heading=",direction);break
		print("METROPOLIS_SITE_SURVEY ",JSON.stringify({"ok":site.get("ok",false),"attempts":site.get("attempts",0),"road_rejections":site.get("road_rejections",{}),"lot_rejections":site.get("lot_rejections",{}),"street_candidates":site.get("street_candidates",0),"grid_rejections":site.get("grid_rejections",0),"best_missing":site.get("best_missing",0)}))
		finish();return
	if "--catalog-only" in OS.get_cmdline_user_args():finish();return
	var progress:=preload("res://addons/world_runtime/world_plan_progress.gd").new()
	var worker:=Thread.new();worker.start(Plan.build.bind(seed_value,GENERATOR,true,true,"user://generation_plans",options,progress))
	var previous:="";var next:=Time.get_ticks_msec()
	while worker.is_alive():
		if Time.get_ticks_msec()>=next:
			var state:Dictionary=progress.snapshot();var activity:String=state.get("activity","")
			if activity!=previous:print("METROPOLIS_PROGRESS ",activity);previous=activity
			next=Time.get_ticks_msec()+2000
		await process_frame
	var plan:Dictionary=worker.wait_to_finish()
	var summary:Dictionary={"seed":seed_value,"ok":plan.get("ok",false),"reason":plan.get("reason",""),"audit":plan.get("metropolis_audit",{}),"worker_ms":plan.get("worker_ms",0),"cache_hit":plan.get("cache_hit",false)}
	summary["sites"]=plan.get("sites",[]).map(func(site:Dictionary):return {"title":site.title,"center":str(site.center),"buildings":site.lots.size()})
	summary["bridges"]=plan.get("bridges",[]).map(func(bridge:Dictionary):return {"kind":bridge.kind,"span":bridge.span,"crossing_type":bridge.get("crossing_type","lake"),"center":str((bridge.banks[0]+bridge.banks[1])*.5)})
	check(plan.get("ok",false),"complete terrain-fitting metropolis: "+str(plan.get("reason","")))
	if plan.get("ok",false):
		if "--trace-contacts" in OS.get_cmdline_user_args():trace_contacts(plan);finish();return
		check(plan.sites.size()==9 and plan.building_count>=84,"complete city blocks and outlying communities")
		check(plan.metropolis_audit.ok,"required content, bridge sizes and regional coverage all pass")
		var resident_lots:Array=[]
		for site:Dictionary in plan.sites:resident_lots.append_array(site.lots)
		check(preload("res://addons/characters/runtime/house_sleepers.gd").plan(resident_lots,seed_value).get("ok",false),"normal resident anchors admit only proved foundation variants")
		check(plan.navigation.places.filter(func(place:Dictionary):return int(place.id) in [3000,3001,3002]).size()==3,"all three grand buildings are named map destinations")
		for site:Dictionary in plan.sites:check(site.lots.all(func(lot:Dictionary):return lot.quality.status=="pass"),"unchanged earthworks limits: "+site.title)
		var cached:Dictionary=Plan.build(seed_value,GENERATOR,true,true,"user://generation_plans",options)
		check(cached.get("ok",false) and cached.get("cache_hit",false) and cached.plan_digest==plan.plan_digest,"same content/seed reuses exact validated plan")
		if "--rebuild-identity" in OS.get_cmdline_user_args():
			var identity_folder:=""
			for argument:String in OS.get_cmdline_user_args():
				if argument.begins_with("--derived-cache="):identity_folder=argument.trim_prefix("--derived-cache=").path_join("identity")
			var identity_worker:=Thread.new();identity_worker.start(Plan.build.bind(seed_value,GENERATOR,true,true,identity_folder,options))
			while identity_worker.is_alive():await process_frame
			var independent:Dictionary=identity_worker.wait_to_finish()
			check(independent.get("ok",false) and independent.get("plan_digest","")==plan.plan_digest,"independent native rebuild has identical geometry identity despite different worker timings")
		check(float(plan.road_normalization.max_shift)<=.555,"complete road curves retain the original displacement limit")
		if "--publication-cells" in OS.get_cmdline_user_args():summary["publication_cells"]=verify_publication_cells(plan)
		if "--preview" in OS.get_cmdline_user_args():summary["preview"]=await normal_preview(plan)
		if "--contacts" in OS.get_cmdline_user_args():summary["contacts"]=await verify_contacts(plan)
	FileAccess.open(folder.path_join("metropolis_recipe.json"),FileAccess.WRITE).store_string(JSON.stringify(summary,"  "))
	finish()
func verify_publication_cells(plan:Dictionary)->Dictionary:
	var blocks=ClassDB.instantiate("NativeBlockWorld")
	var result:Dictionary={"ok":true,"placed_buildings":0,"placed_bridges":0,"paving_cells":0}
	for site:Dictionary in plan.sites:
		for lot:Dictionary in site.lots:
			var cells=ClassDB.instantiate("NativeBlockPrefab");cells.configure(lot.asset.get_records())
			if not blocks.place_prefab(cells,lot.origin,lot.rotation,false):
				result={"ok":false,"phase":"building","label":lot.label,"stats":blocks.stats()};break
			result.placed_buildings+=1
		if not result.ok:break
	if result.ok:
		for crossing:Dictionary in plan.bridges:
			var asset:Resource=preload("res://addons/structures/lake_crossings.gd").asset(crossing)
			if not blocks.place_prefab(asset,crossing.origin,crossing.rotation,false):result={"ok":false,"phase":"bridge","stats":blocks.stats()};break
			result.placed_bridges+=1
	if result.ok:
		for site:Dictionary in plan.sites:
			var records:PackedInt32Array=site.block_paving.records
			if records.is_empty():continue
			var cells=ClassDB.instantiate("NativeBlockPrefab");cells.configure(records)
			if not blocks.place_prefab(cells,Vector3i.ZERO,0,false):
				var overlaps:Array=[];var overlap_count:=0
				for at in range(0,records.size(),4):
					var p:=Vector3i(records[at],records[at+1],records[at+2]);var existing:int=blocks.get_cell(p)
					if existing!=0:
						overlap_count+=1
						if overlaps.size()<8:overlaps.append({"position":str(p),"old":existing,"new":records[at+3]})
				result={"ok":false,"phase":"paving","site":site.title,"overlaps":overlaps,"overlap_count":overlap_count,"stats":blocks.stats()};break
			result.paving_cells+=records.size()/4
	check(result.ok,"all building, bridge and paving cells publish without overlap or capacity failure")
	print("METROPOLIS_PUBLICATION_CELLS ",JSON.stringify(result));blocks.free();return result

func finish()->void:
	print("METROPOLIS_RECIPE checks=",checks," failures=",failures);quit(1 if failures else 0)

func test_components()->void:
	var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,GENERATOR]))
	var segment:=Metro.Lots._segment(Vector3(500,44,120),Vector3(620,44,120),3,3,4,0,4)
	var fitted:Dictionary=core.plan_streets([segment],PackedVector3Array([segment.start,segment.finish]))
	check(fitted.get("ok",false),"native component fixture fits real coastal terrain")
	if not fitted.get("ok",false):return
	var exits:Array=[PackedVector3Array([fitted.segments[0].start]),PackedVector3Array([fitted.segments[fitted.segments.size()-3].finish])]
	var connected:Dictionary=core.plan_region_network(exits,[],0,0,1703,fitted.segments)
	check(connected.get("ok",false) and connected.existing_connections==1 and connected.links.is_empty(),"an existing connected street does not receive a duplicate spanning road")
	var upper:Dictionary=segment.duplicate();upper.start=Vector3(560,54,70);upper.finish=Vector3(560,54,170)
	var separate:Dictionary=core.plan_region_network([PackedVector3Array([segment.start]),PackedVector3Array([upper.start])],[],0,0,1703,[segment,upper])
	check(not separate.get("ok",false) or separate.get("existing_connections",0)==0,"grade-separated crossings remain separate street components")
	var curved:Dictionary=segment.duplicate();curved["coefficients"]=PackedFloat64Array([0,-4,4,44]);curved["curve_index"]=0
	upper.start.y=44;upper.finish.y=44
	separate=core.plan_region_network([PackedVector3Array([curved.start]),PackedVector3Array([upper.start])],[],0,0,1703,[curved,upper])
	check(not separate.get("ok",false) or separate.get("existing_connections",0)==0,"connectivity evaluates the actual cubic height at a crossing")
	check(not core.plan_region_network(exits,[],0,0,1703,fitted.segments,4.9).get("ok",false) and not core.plan_region_network(exits,[],0,0,1703,fitted.segments,8.1).get("ok",false),"unknown road support envelopes reject atomically")
	for rise in [.72,1.12,1.42]:
		var road:Dictionary=segment.duplicate();road.start.y=44.08;road.finish.y=44.08+rise
		road["support_half_width"]=5.5;road["support_shoulder"]=2.0
		var result:Dictionary=core.fit_road_network([road],[],true)
		check(result.get("ok",false),"contact optimization fits a shallow real-terrain curve: "+str(result.get("reason","")))
		if not result.get("ok",false):continue
		var bounded:=true
		for part:Dictionary in result.segments:
			var curve:PackedFloat64Array=part.coefficients;var at:int=int(part.curve_index)*4
			for step in 33:
				var t:float=step/32.0;var point:Vector3=part.start.lerp(part.finish,t)
				var height:float=((curve[at]*t+curve[at+1])*t+curve[at+2])*t+curve[at+3]
				var original:float=road.start.y+(point.x-road.start.x)/(road.finish.x-road.start.x)*rise
				bounded=bounded and absf(height-original)<=.555
		check(bounded,"independent dense samples retain the full-curve displacement limit")

func normal_preview(plan:Dictionary)->Dictionary:
	var browser:Control=load("res://demo/worlds.tscn").instantiate();browser.preview_mode=true;root.add_child(browser)
	browser.session=preload("res://addons/world_runtime/world_session.gd").obtain(self)
	browser.seed_field.value=seed_value
	preload("res://demo/world_creation_panel.gd").apply_style(browser,6)
	await browser.start_preview()
	while browser.preview_worker!=null:
		browser.poll_preview();await process_frame
	check(browser.preview_view.texture!=null and browser.preview_status.text.contains("6 outlying"),"ordinary browser preview displays the complete metropolis recipe")
	var status:String=browser.preview_status.text
	if "--browser-capture" in OS.get_cmdline_user_args():
		browser.world_tabs.current_tab=1
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(folder.path_join("browser.png"))==OK,"ordinary metropolis creation screen retained")
	browser.free()
	var preview:Dictionary=Plan.preview(seed_value,GENERATOR,true,true,true,"user://cartography/generation",Recipe.METROPOLIS)
	check(preview.get("ok",false) and preview.get("plan_digest","")==plan.plan_digest,"native final-surface preview reuses the exact generation plan")
	if preview.get("ok",false):
		var picture:=Image.create_from_data(256,256,false,Image.FORMAT_RGBA8,preview.pixels)
		check(picture.save_png(folder.path_join("map.png"))==OK,"bounded native map preview retained")
	return {"status":status,"ok":preview.get("ok",false),"reason":preview.get("reason","")}

func verify_contacts(plan:Dictionary)->Dictionary:
	var contract=preload("res://tests/terrain_block_contract.gd")
	var field=contract.Field.new();root.add_child(field);field.core=ClassDB.instantiate("TerrainCore")
	field.core.execute(Codec.command(6,[seed_value,GENERATOR]))
	var packets:Array=contract.Works.packets(plan.works.segments,plan.get("material_deposits",[]))
	var baked:Dictionary=field.core.bake_generated_earthworks(packets)
	check(baked.get("ok",false),"normal final terrain bake for all metropolis sites")
	if not baked.get("ok",false):field.free();return {"ok":false,"reason":baked.get("reason","")}
	field.density_revision=baked.revision
	var lake_definitions:Dictionary=preload("res://addons/volumetric_terrain/generated_lakes.gd").describe(field.core,GENERATOR)
	var lake_audit:Dictionary=field.core.survey_generated_lake_surfaces(lake_definitions.records)
	check(lake_audit.get("extensive_count",0)>=3,"all three long lakes stay connected after city, roads and bridges are baked")
	var passed:=0;var rejected:Array=[]
	var inspected_sites:Array=[] if "--bridges-only" in OS.get_cmdline_user_args() else plan.sites
	for site:Dictionary in inspected_sites:
		for lot:Dictionary in site.lots:
			field.validator=contract.Check.new()
			var begun:bool=field.validator.begin(field,lot.asset,lot.origin,lot.rotation)
			var deadline:=Time.get_ticks_msec()+120000
			while field.validator.status=="checking" and Time.get_ticks_msec()<deadline:
				field.validator.tick(field);await process_frame
			var supported:bool=begun and field.validator.status=="supported"
			check(supported,"production support/interior/surface gate: "+lot.label+" / "+field.validator.status)
			if supported:passed+=1
			else:
				var detail:Dictionary={"label":lot.label,"origin":str(lot.origin),"rotation":lot.rotation,"status":field.validator.status,"point":str(field.validator.failure_point)}
				if field.validator.status.begins_with("Unsupported"):
					var probes:PackedVector3Array=lot.asset.foundation_samples(lot.origin,lot.rotation,int(lot.asset.get_meta("site_sample_band",0)))
					for at in range(0,probes.size(),256):
						var batch:=probes.slice(at,at+256);var query:=Codec.command(29,[baked.revision,batch.size()]);query.append_array(batch.to_byte_array())
						var reply:PackedByteArray=field.core.execute(query)
						for index in batch.size():
							if reply.decode_float(20+index*4)>=0:detail.point=str(batch[index]);break
						if detail.point!="(inf, inf, inf)":break
				print("METROPOLIS_CONTACT_REJECTION ",JSON.stringify(detail));rejected.append(detail)
		var plates:Resource=ClassDB.instantiate("NativeBlockPrefab");plates.configure(site.block_paving.records);field.validator=contract.Check.new()
		var begun:bool=field.validator.begin_surfaces_only(field,plates,Vector3i.ZERO,0)
		while field.validator.status=="checking":field.validator.tick(field);await process_frame
		check(begun and field.validator.status=="supported","all final sidewalk surfaces: "+site.title+" / "+field.validator.status)
	var bridge_failures:=0
	for bridge:Dictionary in plan.get("bridges",[]):
		var asset:Resource=preload("res://addons/structures/lake_crossings.gd").asset(bridge)
		field.validator=contract.Check.new()
		var begun:bool=field.validator.begin_surfaces_only(field,asset,bridge.origin,bridge.rotation)
		while field.validator.status=="checking":field.validator.tick(field);await process_frame
		var clear:bool=begun and field.validator.status=="supported"
		check(clear,"final bridge deck and bank surfaces: %d m / %s"%[bridge.span,field.validator.status])
		if not clear:bridge_failures+=1
		var axis:Vector3=(bridge.banks[1]-bridge.banks[0]).normalized();var roots:=PackedVector3Array()
		for probe:Vector3 in asset.foundation_samples(bridge.origin,bridge.rotation,0):
			var along:float=(probe-bridge.banks[0]).dot(axis)
			if along<=.75 or along>=float(bridge.span)-1.25:roots.append(probe)
		var query:=Codec.command(30,[baked.revision,roots.size(),8]);query.append_array(roots.to_byte_array())
		var reply:PackedByteArray=field.core.execute(query)
		var supported:bool=not roots.is_empty() and Codec.reply_ok(reply)
		if supported:
			for index in roots.size():supported=supported and reply.decode_float(20+index*4)<0
		check(supported,"both real bridge end footings have deep terrain support: %d m"%bridge.span)
		if not supported:bridge_failures+=1
	field.free()
	lake_audit.erase("points")
	return {"ok":rejected.is_empty() and bridge_failures==0,"buildings_passed":passed,"rejected":rejected,"bridge_failures":bridge_failures,"lakes":lake_audit}

func trace_contacts(plan:Dictionary)->void:
	var works=preload("res://addons/world_runtime/generation_earthworks.gd")
	var ordered:Array=works.ordered_segments(plan.works.segments)
	for point:Vector3 in [Vector3(309.5,41.75,76.5),Vector3(1893.5,43.75,596.5),Vector3(138.5,45.75,1356.5)]:
		var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,GENERATOR]))
		var previous:=INF;var count:=0
		for index in ordered.size():
			var segment:Dictionary=ordered[index]
			if not segment.bounds.grow(8).has_point(point):continue
			var reply:PackedByteArray=core.execute(works.packets([segment])[0])
			if not Codec.reply_ok(reply):print("TRACE_APPLY_FAILED ",index);continue
			var query:=Codec.command(29,[reply.decode_u32(12),1]);query.append_array(PackedVector3Array([point]).to_byte_array())
			var sample:PackedByteArray=core.execute(query);var density:=sample.decode_float(20)
			if count==0 or (density>=0)!=(previous>=0):
				print("CONTACT_STAMP_TRACE ",JSON.stringify({"point":str(point),"density":density,"prior":str(previous),"index":index,"phase":segment.get("phase",""),"start":str(segment.start),"finish":str(segment.finish),"width":segment.half_width,"clearance":segment.clearance,"shoulder":segment.shoulder,"cut_only":segment.get("cut_only",false)}))
			previous=density;count+=1
		print("CONTACT_STAMP_FINAL ",point," density=",previous," stamps=",count)

func locate_only()->void:
	var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,GENERATOR]))
	var progress:=preload("res://addons/world_runtime/world_plan_progress.gd").new()
	var worker:=Thread.new();worker.start(Metro.locate.bind(core,3,0,progress))
	var previous:="";var next:=Time.get_ticks_msec()
	while worker.is_alive():
		if Time.get_ticks_msec()>=next:
			var state:Dictionary=progress.snapshot();var activity:String=state.get("activity","")
			if activity!=previous:print("METROPOLIS_PROGRESS ",activity);previous=activity
			next=Time.get_ticks_msec()+2000
		await process_frame
	var result:Dictionary=worker.wait_to_finish()
	check(result.get("ok",false),"diagnostic city and community fitting: "+str(result.get("reason","")))
	var summary:Dictionary={"ok":result.get("ok",false),"reason":result.get("reason",""),"sites":[]}
	for site:Dictionary in result.get("sites",[]):summary.sites.append({"title":site.title,"center":str(site.center),"lots":site.lots.size()})
	FileAccess.open(folder.path_join("metropolis_recipe.json"),FileAccess.WRITE).store_string(JSON.stringify(summary,"  "))
	finish()
