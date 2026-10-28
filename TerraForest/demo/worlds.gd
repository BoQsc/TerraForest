# SPDX-License-Identifier: 0BSD
extends Control
const Mouse=preload("res://addons/world_runtime/mouse_ownership.gd")
const Launch=preload("res://demo/world_launch.gd")
var worlds: ItemList
var name_field: LineEdit
var seed_field: SpinBox
var preset: OptionButton
var ocean:CheckBox
var buildable_ground:CheckBox
var buildable_roads:CheckBox
var material_veins:CheckBox
var biome:OptionButton
var settlement_count:OptionButton
var district_count:OptionButton
var road_network:OptionButton
var offroads:OptionButton
var world_style:OptionButton
var style_description:Label
var recipe_summary:Label
var preview_metrics:Label
var preview_empty:Label
var preview_started:=0
var plan_progress:RefCounted
var gameplay: CheckBox
var notice: Label
var filter_field: LineEdit
var show_preparation:CheckBox
var sort_order:OptionButton
var saved_picture:TextureRect
var saved_details:Label
var saved_title:Label
var preview_view:TextureRect
var preview_status:Label
var preview_worker:Thread
var preview_key:=""
var preview_button:Button
var generate_button:Button
var shuffle_button:Button
var world_tabs:TabContainer
var preparation_panel:PanelContainer
const PREVIEW_DELAY_MS:=350
var preview_due_ms:=-1
var slots:=PackedStringArray()
var photograph_pid:=-1
var photograph_job:Node
var photograph_cancelling:=false
var preparation_job:Node
var session:Node
var photograph_log:=""
var photograph_deadline:=0
var photograph_slot:=""
var photograph_button:Button
var photograph_cancel:Button
var preparation_pid:=-1
var preparation_status:=""
var preparation_slot:=""
var preparation_gameplay:=true
var preparation_poll:=0.0
var preparation_started_msec:=0
var preparation_cancel:=""
var cancel_pending:=false
var quit_pending:=false
var cancel_button:Button
var generation_screen:CanvasLayer
func heading(parent: Node,text: String,size: int=24) -> Label:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size);parent.add_child(label);return label
func button(parent: Node,text: String,action: Callable) -> Button:
	var out:=Button.new();out.text=text;out.custom_minimum_size.y=48;out.pressed.connect(action);parent.add_child(out);return out
func _ready() -> void:
	preload("res://addons/world_runtime/session_options.gd").reset()
	session=preload("res://addons/world_runtime/world_session.gd").obtain(get_tree())
	get_tree().auto_accept_quit=false
	Engine.max_fps=60;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Mouse.set_mode(self,Input.MOUSE_MODE_VISIBLE)
	preload("res://demo/world_creation_panel.gd").apply_theme(self)
	var background:=ColorRect.new();background.color=Color("0b171d");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var margin:=MarginContainer.new();margin.add_theme_constant_override("margin_left",48);margin.add_theme_constant_override("margin_right",48);margin.add_theme_constant_override("margin_top",24);margin.add_theme_constant_override("margin_bottom",20);add_child(margin)
	get_viewport().size_changed.connect(_fit_browser.bind(margin));_fit_browser(margin)
	var panel:=VBoxContainer.new();panel.add_theme_constant_override("separation",14);margin.add_child(panel)
	var branding:=HBoxContainer.new();panel.add_child(branding)
	var title:=heading(branding,"TERRAFOREST",32);title.add_theme_color_override("font_color",Color("91d5b4"));title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading(branding,"WORLDS / YOUR NEXT CHAPTER",16)
	var columns:=TabContainer.new();columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;panel.add_child(columns)
	world_tabs=columns
	columns.tab_changed.connect(func(index:int):
		if index==1 and preview_view!=null and preview_view.texture==null:preview_due_ms=Time.get_ticks_msec()+PREVIEW_DELAY_MS)
	var saved:=VBoxContainer.new();saved.name="My worlds";saved.custom_minimum_size.x=850;saved.add_theme_constant_override("separation",16);columns.add_child(saved)
	heading(saved,"Saved worlds")
	sort_order=OptionButton.new();sort_order.add_item("Last played · newest first");sort_order.add_item("Created · newest first");sort_order.add_item("Name");sort_order.item_selected.connect(func(_index:int):refresh());saved.add_child(sort_order)
	sort_order.tooltip_text="Older worlds without recorded dates fall back to their last save time."
	var filters:=HBoxContainer.new();saved.add_child(filters)
	filter_field=LineEdit.new();filter_field.size_flags_horizontal=Control.SIZE_EXPAND_FILL;filter_field.placeholder_text="Filter saved worlds";filter_field.text_changed.connect(func(_text: String):filter_list());filters.add_child(filter_field)
	show_preparation=CheckBox.new();show_preparation.text="Generation drafts (developer, read-only)";show_preparation.visible="--developer-worlds" in OS.get_cmdline_user_args();show_preparation.toggled.connect(func(_on:bool):refresh());filters.add_child(show_preparation)
	var library:=HBoxContainer.new();library.add_theme_constant_override("separation",28);library.size_flags_vertical=Control.SIZE_EXPAND_FILL;saved.add_child(library)
	worlds=ItemList.new();worlds.size_flags_vertical=Control.SIZE_EXPAND_FILL;worlds.size_flags_horizontal=Control.SIZE_EXPAND_FILL;worlds.custom_minimum_size=Vector2(300,250);library.add_child(worlds)
	var detail_column:=VBoxContainer.new();detail_column.custom_minimum_size.x=380;detail_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;library.add_child(detail_column)
	saved_title=heading(detail_column,"Select a world",24)
	saved_picture=TextureRect.new();saved_picture.custom_minimum_size=Vector2(380,200);saved_picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;saved_picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;detail_column.add_child(saved_picture)
	saved_details=heading(detail_column,"",18);saved_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	worlds.item_selected.connect(show_saved_details)
	button(saved,"Open selected world",func():launch_selected(false))
	var library_actions:=HBoxContainer.new();saved.add_child(library_actions)
	button(library_actions,"Refresh saved worlds",refresh)
	photograph_button=button(library_actions,"Refresh photographs",refresh_photographs)
	photograph_cancel=button(library_actions,"Cancel photographs",cancel_photographs);photograph_cancel.hide()
	button(library_actions,"Recover interrupted publication",show_recovery)
	preload("res://demo/world_creation_panel.gd").build(self,columns)
	gameplay=CheckBox.new();gameplay.text="Gameplay material costs (uncheck for free editor)";gameplay.button_pressed=true;panel.add_child(gameplay)
	var bottom:=HBoxContainer.new();bottom.alignment=BoxContainer.ALIGNMENT_END;panel.add_child(bottom)
	notice=heading(bottom,"",16);notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;notice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(bottom,"Quit",request_quit)
	refresh()
	if not session.last_error.is_empty():notice.text=session.last_error;session.last_error=""
func _fit_browser(panel:Control)->void:
	var available:=get_viewport_rect().size
	var factor:=clampf(minf(available.y/900.0,available.x/1280.0),0.5,1.0)
	panel.scale=Vector2.ONE*factor;panel.size=available/factor
func refresh() -> void:
	if preparation_pid>=0 or photograph_pid>=0:return
	slots=Launch.saved_slots("user://worlds",show_preparation.button_pressed,["played","created","name"][sort_order.selected]);filter_list()
	notice.text="%d saved worlds. Save from the Actions menu or with F5 while playing."%slots.size()
func filter_list() -> void:
	var selected:=""
	if not worlds.get_selected_items().is_empty():selected=str(worlds.get_item_metadata(worlds.get_selected_items()[0]))
	worlds.clear()
	for slot: String in slots:
		if filter_field.text.is_empty() or slot.to_lower().contains(filter_field.text.to_lower()):
			worlds.add_item(("[Preparation] " if Launch.preparation_slot(slot) else "")+slot)
			worlds.set_item_metadata(worlds.item_count-1,slot)
	if worlds.item_count>0:
		var index:=0
		for i in worlds.item_count:
			if str(worlds.get_item_metadata(i))==selected:index=i;break
		worlds.select(index);show_saved_details(index)
	else:saved_title.text="No matching worlds";saved_picture.texture=null;saved_details.text=""
func show_saved_details(index:int)->void:
	if index<0 or index>=worlds.item_count:return
	var slot:=str(worlds.get_item_metadata(index))
	var presentation=preload("res://addons/world_runtime/world_presentation.gd")
	var data:Dictionary=presentation.details(slot)
	saved_title.text=slot
	saved_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	saved_picture.texture=presentation.image_for(slot)
	var lines:=PackedStringArray()
	for entry in [["created","Created"],["last_played","Last played"],["saved","Last saved"]]:
		var value:int=int(data.get(entry[0],0))
		lines.append(entry[1]+": "+(Time.get_datetime_string_from_unix_time(value,true)+" UTC" if value>0 else "Not recorded"))
	if data.has("seed"):lines.append("Seed: "+str(int(data.seed)))
	if data.has("generator"):
		var id:int=int(data.generator)
		lines.append("Landscape: "+({17:"Regional inland",18:"Regional inland",19:"Regional coast",20:"Build-friendly inland",21:"Build-friendly coast",22:"Grid-preferred inland",23:"Grid-preferred coast",13:"Earlier regional recipe"}.get(id,Launch.PRESETS.get(id,"Saved recipe "+str(id)))))
	if data.has("settlement_layout"):lines.append("Layout: "+str(data.settlement_layout).capitalize())
	var options:Dictionary=data.get("world_options",{})
	if options.has_all(["settlements","districts","biome"]) and int(options.biome) in [0,1,2]:lines.append("%d settlements · %d districts · %s"%[int(options.settlements),int(options.settlements)*int(options.districts),["Woodland","Woodland & meadow mosaic","Open grassland with groves"][int(options.biome)]])
	if options.has("road_grid"):lines.append("Road grid preference: "+("On" if int(options.road_grid)>0 else "Off"))
	if saved_picture.texture==null:lines.append("No cached photograph yet.")
	lines.append("Opening uses this world's saved generation settings.")
	saved_details.text="\n".join(lines)
func launch_selected(create: bool) -> void:
	if preparation_pid>=0 or photograph_pid>=0:return
	var slot:=name_field.text.strip_edges()
	if create and slot.is_empty():
		slot=Launch.generated_world_name();name_field.text=slot
	if not create:
		if worlds.get_selected_items().is_empty():notice.text="Select a saved world first.";return
		slot=str(worlds.get_item_metadata(worlds.get_selected_items()[0]))
	var layout:="connected" if settlement_count.selected>0 else "settlement"
	var result:=Launch.command(slot,create,preset.get_selected_id(),int(seed_field.value),gameplay.button_pressed,"user://worlds",ocean.button_pressed,layout,buildable_ground.button_pressed,selected_options() if create else {})
	if not result.ok:notice.text=result.reason;return
	if result.get("prepare",false):
		start_preparation(result,slot);return
	# The browser owns no world worker or canonical save. Launch one world and
	# exit the browser instead of replacing a live world's storage ownership.
	_open_game(result.args)

var preparation_started_unix_ms:=0

func start_preparation(result:Dictionary,slot:String)->void:
	if preparation_pid>=0 or photograph_pid>=0:return
	preparation_started_unix_ms=preload("res://addons/world_runtime/loading_timer.gd").unix_milliseconds()
	result.args.append("--loading-started-ms="+str(preparation_started_unix_ms))
	preparation_slot=slot;preparation_gameplay=gameplay.button_pressed
	preparation_status="user://world_preparation_%d_%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	preparation_cancel=preparation_status+".cancel";cancel_pending=false
	result.args.append_array(PackedStringArray(["--status-file="+ProjectSettings.globalize_path(preparation_status),"--cancel-file="+ProjectSettings.globalize_path(preparation_cancel)]))
	preparation_pid=OS.get_process_id();preparation_started_msec=Time.get_ticks_msec()
	world_tabs.current_tab=1;_set_creation_busy(true)
	preview_due_ms=-1
	preparation_panel.reset(preparation_started_unix_ms)
	preparation_panel.show_progress("Generating "+slot,"Finishing the current preview…" if preview_worker!=null else "Starting world generation…",0)
	cancel_button.disabled=false
	# Reuse the finished plan without racing its cache writer or blocking the UI.
	while preview_worker!=null:await get_tree().process_frame
	if cancel_pending:
		preparation_pid=-1;_set_creation_busy(false)
		notice.text="Generation cancelled. Existing saves are preserved."
		if quit_pending:get_tree().quit()
		return
	preparation_job=preload("res://addons/world_runtime/scene_job.gd").new();session.add_child(preparation_job)
	preparation_job.start(preload("res://addons/world_runtime/generation_coordinator.gd"),preload("res://addons/world_runtime/session_options.gd").user_arguments(result.args),false)
	Engine.max_fps=60
	notice.text="Generating %s. Your world will load automatically when it is ready."%slot

func _set_creation_busy(active:bool)->void:
	notice.visible=not active
	world_tabs.set_tab_disabled(0,active)
	generate_button.text="Cancel" if active else "Generate & play";generate_button.disabled=false
	shuffle_button.disabled=active;gameplay.disabled=active
	world_style.disabled=active or preset.get_selected_id()!=Launch.INTEGRATED_PRESET
	preview_button.disabled=active or preview_worker!=null
	name_field.editable=not active;seed_field.editable=not active
	for toggle:CheckBox in [ocean,buildable_ground,buildable_roads,material_veins]:toggle.disabled=active
	for option:OptionButton in [preset,biome,settlement_count,district_count,road_network,offroads]:
		option.disabled=active or (option!=preset and preset.get_selected_id()!=Launch.INTEGRATED_PRESET)
	if not active:preparation_panel.show_idle();update_recipe_summary()

func show_recovery()->void:
	if preparation_pid>=0 or photograph_pid>=0:return
	var dialog:=ConfirmationDialog.new();dialog.title="Recover interrupted publication";dialog.ok_button_text="Recover";dialog.min_size=Vector2i(580,220)
	var content:=VBoxContainer.new();dialog.add_child(content)
	var label:=Label.new();label.text="Enter the original world name. Recovery verifies existing staged data;\nit does not generate a different world or replace a published save.";content.add_child(label)
	var field:=LineEdit.new();field.placeholder_text="Original world name";content.add_child(field)
	dialog.confirmed.connect(func():
		var slot:=field.text.strip_edges();var result:=Launch.recovery_command(slot)
		if result.ok:start_preparation(result,slot)
		else:notice.text=result.reason
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog);dialog.popup_centered();field.grab_focus()

func _process(delta:float)->void:
	poll_preview()
	if photograph_pid>=0:
		if not photograph_job.done:
			if Time.get_ticks_msec()>photograph_deadline and not photograph_cancelling:cancel_photographs();notice.text="Photograph capture timed out. Saved world unchanged."
			return
		var code:int=photograph_job.code;photograph_job.queue_free();photograph_job=null
		photograph_pid=-1;Engine.max_fps=60;photograph_button.disabled=false;photograph_cancel.hide()
		if generation_screen!=null:generation_screen.queue_free();generation_screen=null
		refresh()
		notice.text="Photograph capture cancelled. Saved world unchanged." if photograph_cancelling else ("Photographs refreshed for "+photograph_slot+"." if code==0 else "Photograph capture failed. Saved world unchanged.")
		photograph_cancelling=false
		if quit_pending:get_tree().quit()
		return
	if preparation_pid<0:return
	if preparation_job==null:return # Waiting for an already-running preview.
	preparation_poll-=delta
	if preparation_poll>0:return
	preparation_poll=0.5
	if not preparation_job.done:
		_update_preparation_notice();return
	preparation_pid=-1;preparation_job.queue_free();preparation_job=null;Engine.max_fps=60
	_set_creation_busy(false)
	var result:Variant=JSON.parse_string(FileAccess.get_file_as_string(preparation_status)) if FileAccess.file_exists(preparation_status) else null
	refresh()
	if quit_pending:get_tree().quit();return
	if cancel_pending:
		notice.text="Generation cancelled. Existing saves are preserved."
		if result is Dictionary and result.get("state","")=="ready":notice.text="Generation finished before cancellation. The world is saved; select it when ready to play."
		return
	if not result is Dictionary or result.get("state","")!="ready":
		notice.text="World generation did not finish. Existing saves are preserved. " + (str(result.get("reason",""))+" Logs: "+str(result.get("report","")) if result is Dictionary else "Check the generation report.")
		return
	var launch:=Launch.command(preparation_slot,false,12,0,preparation_gameplay)
	if not launch.ok:notice.text=launch.reason;return
	launch.args.append("--generation-handoff")
	launch.args.append("--loading-started-ms="+str(int(result.get("loading_started_ms",preparation_started_unix_ms))))
	_open_game(launch.args)

func _open_game(args:PackedStringArray)->void:
	# This scene is about to be destroyed; the persistent host owns the await.
	session.open_world(args)

func _update_preparation_notice()->void:
	var result:Variant=JSON.parse_string(FileAccess.get_file_as_string(preparation_status)) if FileAccess.file_exists(preparation_status) else null
	if cancel_pending:
		notice.text="Cancelling generation…"
		preparation_panel.stop_timer("cancelling");preparation_panel.detail.text=notice.text;cancel_button.disabled=true
		return
	var stage:="Starting world generation"
	var state:=str(result.get("state","")) if result is Dictionary else ""
	var detail:Dictionary={}
	if result is Dictionary:
		match str(result.get("state","")):
			"creating":stage="Generating terrain, locations and saved world"
			"verifying":stage="Verifying saved terrain, buildings and water"
			"recovering":stage="Verifying and recovering interrupted publication"
			"publishing":stage="Publishing the verified world"
			"ready":stage="Loading your world"
			"failed":stage="Generation failed; collecting the result"
	if state=="creating" and result is Dictionary and result.get("progress",{}) is Dictionary:
		detail=result.get("progress",{})
		if not str(detail.get("stage","")).is_empty():
			stage=str(detail.get("details",{}).get("activity",detail.stage))
			if int(detail.get("total",0))>0 and not detail.get("details",{}).has("activity"):stage+=" · %d / %d"%[int(detail.get("completed",0)),int(detail.total)]
	preparation_panel.show_progress("Generating "+preparation_slot,stage,preload("res://addons/world_runtime/progress_meter.gd").coordinator(state,detail))
	preparation_panel.show_work(str(detail.get("details",{}).get("work","")))
	if state in ["failed","cancelled"]:preparation_panel.stop_timer(state)
	var elapsed:int=maxi(0,Time.get_ticks_msec()-preparation_started_msec)/1000
	notice.text="%s · %s · %d:%02d"%[preparation_slot,stage,elapsed/60,elapsed%60]

func cancel_preparation()->void:
	if preparation_pid<0 or cancel_pending:return
	var request:=FileAccess.open(preparation_cancel,FileAccess.WRITE)
	if request==null:notice.text="Could not request cancellation. Generation is still running.";return
	request.store_string("cancel");request.close()
	cancel_pending=true;cancel_button.disabled=true
	_update_preparation_notice()
func request_quit()->void:
	if photograph_pid>=0:quit_pending=true;cancel_photographs();return
	if preparation_pid<0:get_tree().quit();return
	cancel_preparation()
	quit_pending=cancel_pending
func _notification(what:int)->void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:request_quit()

func selected_preview_key()->String:
	return "%d/%d/%s"%[int(seed_field.value),Launch.terrain_generator(ocean.button_pressed,buildable_ground.button_pressed),preload("res://addons/world_runtime/world_recipe.gd").encode(selected_options()).hex_encode()] if preset.get_selected_id()==Launch.INTEGRATED_PRESET else "%d/%d"%[int(seed_field.value),preset.get_selected_id()]
func selected_options()->Dictionary:
	if preset.get_selected_id()!=Launch.INTEGRATED_PRESET:return {}
	return {"biome":biome.selected,"settlements":settlement_count.selected+1,"districts":district_count.selected+1,"network":road_network.selected,"trails":offroads.selected,"road_grid":preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS.road_grid if buildable_roads.button_pressed else 0,"material_veins":int(material_veins.button_pressed)}
func update_recipe_summary()->void:
	var towns:=settlement_count.selected+1;var districts:=district_count.selected+1
	recipe_summary.text="%d settlements · %d districts · %s"%[towns,towns*districts,biome.get_item_text(biome.selected)]
	recipe_summary.tooltip_text=recipe_summary.text
func invalidate_preview()->void:
	preload("res://demo/world_creation_panel.gd").sync_style(self)
	preview_view.texture=null
	preview_due_ms=Time.get_ticks_msec()+PREVIEW_DELAY_MS
	preview_empty.show();preview_metrics.text="UPDATING PREVIEW…";update_recipe_summary()
	preview_status.text="The preview updates automatically after you finish changing settings."
func start_preview()->void:
	if preview_worker!=null or preparation_pid>=0 or photograph_pid>=0:return
	preview_due_ms=-1
	var generator:int=Launch.terrain_generator(ocean.button_pressed,buildable_ground.button_pressed)
	if preset.get_selected_id()!=Launch.INTEGRATED_PRESET:generator=preset.get_selected_id()
	if generator>=10000:preview_status.text="Select the current regional world to preview terrain.";return
	preview_started=Time.get_ticks_msec();preview_key=selected_preview_key();preview_status.text="Surveying terrain, fitting districts and connecting roads…";preview_button.disabled=true;preview_empty.hide()
	preview_worker=Thread.new()
	plan_progress=preload("res://addons/world_runtime/world_plan_progress.gd").new()
	var job:Callable=preload("res://addons/world_runtime/world_generation_plan.gd").preview.bind(int(seed_field.value),generator,preset.get_selected_id()==Launch.INTEGRATED_PRESET,true,true,"user://cartography/generation",selected_options(),plan_progress)
	if preview_worker.start(job)!=OK:preview_worker=null;preview_button.disabled=false;preview_status.text="Could not start terrain preview."
func poll_preview()->void:
	if preview_worker==null:
		if preview_due_ms>=0 and Time.get_ticks_msec()>=preview_due_ms and world_tabs.current_tab==1:start_preview()
		return
	if preview_worker.is_alive():
		preview_metrics.text="PLANNING  ·  %.1f s elapsed  ·  Native worker / UI remains interactive"%((Time.get_ticks_msec()-preview_started)/1000.0)
		if plan_progress!=null and preview_key==selected_preview_key():
			var current:Dictionary=plan_progress.snapshot()
			if not current.is_empty():preview_status.text=current.activity+"\n"+current.work
		return
	var completed=preview_worker.wait_to_finish();preview_worker=null;preview_button.disabled=preparation_pid>=0
	if not completed is Dictionary:preview_status.text="Terrain preview failed. Try again after checking the generator log.";return
	var result:Dictionary=completed
	if preview_key!=selected_preview_key():return # A debounced preview of the latest recipe is pending.
	if not result.get("ok",false):preview_status.text=str(result.get("reason","Terrain preview failed."))+" No world was created.";preview_metrics.text="PLAN UNAVAILABLE  ·  Adjust settings or try another seed";preview_empty.show();return
	preview_empty.hide()
	preview_view.texture=ImageTexture.create_from_image(Image.create_from_data(256,256,false,Image.FORMAT_RGBA8,result.pixels))
	if result.has("building_count"):
		preview_status.text="World plan · north is up · 2 km × 2 km\n%d buildings · surface colors\n"%int(result.building_count)
		preview_status.text+="The bake reuses this cached placement plan." if result.get("plan_reusable",false) else "Cache unavailable; generation will repeat this deterministic plan."
		var network:Dictionary=result.get("network",{})
		preview_metrics.text="%d BUILDINGS  ·  %.2f km regional roads  ·  %.2f km trails"%[result.building_count,float(network.get("road_length_m",0))/1000,float(network.get("trail_length_m",0))/1000]
		if result.has("options"):
			preview_status.text="%d settlements / %d districts · %d trails · %d alternate routes.\n"%[result.options.settlements,result.options.settlements*result.options.districts,network.get("trail_count",0),network.get("loop_count",0)]+("Placement plan cached for generation." if result.get("plan_reusable",false) else "Deterministic plan ready; disk cache unavailable.")
			if result.options.network>0 and network.get("loop_count",0)==0:preview_status.text+=" No additional inter-district route fits this plan."
			elif network.get("optional_loops_reduced",false):preview_status.text+=" Optional loops reduced by terrain limits."
			if network.get("trail_count",0)<network.get("requested_trails",0):preview_status.text+=" Some trails could not fit."
	else:preview_status.text="Terrain preview · north is up · 2 km × 2 km"
func _exit_tree()->void:
	if preview_worker!=null:preview_worker.wait_to_finish();preview_worker=null

func refresh_photographs()->void:
	if preparation_pid>=0 or photograph_pid>=0 or worlds.get_selected_items().is_empty():return
	photograph_slot=str(worlds.get_item_metadata(worlds.get_selected_items()[0]))
	var command:=Launch.photograph_command(photograph_slot)
	if not command.ok:notice.text=command.reason;return
	photograph_log=ProjectSettings.globalize_path("user://photograph_%d_%d.log"%[OS.get_process_id(),Time.get_ticks_usec()])
	var args:PackedStringArray=command.args
	var separator:=args.find("--");args.insert(separator,"--log-file");args.insert(separator+1,photograph_log)
	var cancel_path:=photograph_log+".cancel"
	args.append("--cancel-file="+cancel_path)
	photograph_job=preload("res://addons/world_runtime/scene_job.gd").new();session.add_child(photograph_job)
	photograph_job.start(preload("res://addons/world_runtime/capture_world_previews_task.gd"),preload("res://addons/world_runtime/session_options.gd").user_arguments(args))
	photograph_pid=OS.get_process_id();photograph_cancelling=false
	generation_screen=preload("res://addons/world_runtime/generation_screen.gd").new();generation_screen.cancel_path=cancel_path;add_child(generation_screen)
	generation_screen.cancel_requested.connect(cancel_photographs)
	generation_screen.panel.show_progress("Refreshing world photographs","Loading the saved world in an offscreen viewport…",0)
	generation_screen.cancel_button.text="Cancel photographs"
	generation_screen.diagnostics.provider=photograph_job.task.diagnostics
	var photograph:Texture2D=preload("res://addons/world_runtime/world_presentation.gd").image_for(photograph_slot)
	if photograph!=null:generation_screen.picture.texture=photograph
	photograph_job.task.progress_changed.connect(func(stage:String,completed:int,total:int,detail:Dictionary):
		if generation_screen!=null:
			var fraction:float=float(detail.get("stage_fraction",float(completed)/maxi(1,total)))
			generation_screen.panel.show_progress("Refreshing world photographs",str(detail.get("activity",stage)),fraction*100)
			generation_screen.panel.show_work(str(detail.get("work","")))
			generation_screen.diagnostics.observe(stage,{"completed":completed,"total":total,"details":detail}))
	photograph_deadline=Time.get_ticks_msec()+150000
	Engine.max_fps=60;photograph_button.disabled=true;photograph_cancel.disabled=false;photograph_cancel.show()
	notice.text="Photographing "+photograph_slot+" offscreen. Its saved world will not change."
func cancel_photographs()->void:
	if photograph_pid<0:return
	photograph_cancelling=true;photograph_job.cancel();photograph_cancel.disabled=true
	notice.text="Cancelling photograph capture…"
