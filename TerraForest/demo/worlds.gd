# SPDX-License-Identifier: 0BSD
extends Control
const Launch=preload("res://demo/world_launch.gd")
var worlds: ItemList
var name_field: LineEdit
var seed_field: SpinBox
var preset: OptionButton
var ocean:CheckBox
var layout_preset:OptionButton
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
var slots:=PackedStringArray()
var photograph_pid:=-1
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
func heading(parent: Node,text: String,size: int=24) -> Label:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size);parent.add_child(label);return label
func button(parent: Node,text: String,action: Callable) -> Button:
	var out:=Button.new();out.text=text;out.custom_minimum_size.y=48;out.pressed.connect(action);parent.add_child(out);return out
func _ready() -> void:
	get_tree().auto_accept_quit=false
	Engine.max_fps=60;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var background:=ColorRect.new();background.color=Color("101e22");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var panel:=VBoxContainer.new();panel.position=Vector2(160,40);panel.size=Vector2(1600,1000);panel.add_theme_constant_override("separation",12);add_child(panel)
	heading(panel,"TERRAFOREST / WORLDS",36)
	heading(panel,"Choose where to play. Each named world keeps its own saved progress.",20)
	var columns:=TabContainer.new();columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;panel.add_child(columns)
	var saved:=VBoxContainer.new();saved.name="My worlds";saved.custom_minimum_size.x=850;saved.add_theme_constant_override("separation",16);columns.add_child(saved)
	heading(saved,"Saved worlds")
	sort_order=OptionButton.new();sort_order.add_item("Last played · newest first");sort_order.add_item("Created · newest first");sort_order.add_item("Name");sort_order.item_selected.connect(func(_index:int):refresh());saved.add_child(sort_order)
	sort_order.tooltip_text="Older worlds without recorded dates fall back to their last save time."
	var filters:=HBoxContainer.new();saved.add_child(filters)
	filter_field=LineEdit.new();filter_field.size_flags_horizontal=Control.SIZE_EXPAND_FILL;filter_field.placeholder_text="Filter saved worlds";filter_field.text_changed.connect(func(_text: String):filter_list());filters.add_child(filter_field)
	show_preparation=CheckBox.new();show_preparation.text="Preparation saves (read-only)";show_preparation.toggled.connect(func(_on:bool):refresh());filters.add_child(show_preparation)
	var library:=HBoxContainer.new();library.add_theme_constant_override("separation",28);library.size_flags_vertical=Control.SIZE_EXPAND_FILL;saved.add_child(library)
	worlds=ItemList.new();worlds.size_flags_vertical=Control.SIZE_EXPAND_FILL;worlds.size_flags_horizontal=Control.SIZE_EXPAND_FILL;worlds.custom_minimum_size=Vector2(600,300);library.add_child(worlds)
	var detail_column:=VBoxContainer.new();detail_column.custom_minimum_size.x=660;library.add_child(detail_column)
	saved_title=heading(detail_column,"Select a world",24)
	saved_picture=TextureRect.new();saved_picture.custom_minimum_size=Vector2(660,200);saved_picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;saved_picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;detail_column.add_child(saved_picture)
	saved_details=heading(detail_column,"",18);saved_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	worlds.item_selected.connect(show_saved_details)
	button(saved,"Open selected world",func():launch_selected(false))
	var library_actions:=HBoxContainer.new();saved.add_child(library_actions)
	button(library_actions,"Refresh saved worlds",refresh)
	photograph_button=button(library_actions,"Refresh photographs",refresh_photographs)
	photograph_cancel=button(library_actions,"Cancel photographs",cancel_photographs);photograph_cancel.hide()
	button(library_actions,"Recover interrupted publication",show_recovery)
	var create_page:=HBoxContainer.new();create_page.name="Create world";create_page.add_theme_constant_override("separation",40);columns.add_child(create_page)
	var create:=VBoxContainer.new();create.custom_minimum_size.x=600;create.add_theme_constant_override("separation",8);create_page.add_child(create)
	heading(create,"Create a world")
	heading(create,"World name",18);name_field=LineEdit.new();name_field.placeholder_text="e.g. woodland_home";name_field.max_length=48;create.add_child(name_field)
	heading(create,"Landscape",18);preset=OptionButton.new();create.add_child(preset)
	for id: int in Launch.PRESETS:preset.add_item(Launch.PRESETS[id],id)
	preset.select(0)
	ocean=CheckBox.new();ocean.text="Surrounding ocean and beaches";ocean.button_pressed=true;create.add_child(ocean)
	ocean.tooltip_text="Applies to new terrain-fitted worlds. Existing worlds keep their saved coastline."
	preset.item_selected.connect(func(_index:int):ocean.visible=preset.get_selected_id()==Launch.INTEGRATED_PRESET)
	layout_preset=OptionButton.new();layout_preset.add_item("Two settlements with connecting road");layout_preset.add_item("One settlement with regional road");layout_preset.add_item("One standalone settlement");create.add_child(layout_preset)
	layout_preset.tooltip_text="Changes the actual cached placement plan used by preview and generation."
	layout_preset.item_selected.connect(func(_index:int):invalidate_preview())
	preset.item_selected.connect(func(_index:int):layout_preset.visible=preset.get_selected_id()==Launch.INTEGRATED_PRESET)
	heading(create,"Seed",18);seed_field=SpinBox.new();seed_field.min_value=0;seed_field.max_value=2147483647;seed_field.step=1;seed_field.value=1703;create.add_child(seed_field)
	var explanation:=heading(create,"The seed and landscape apply only to new worlds. Saved worlds retain their generation settings. Integrated worlds are prepared and verified before play; first creation can take several minutes.",18);explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var map_column:=VBoxContainer.new();map_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;create_page.add_child(map_column)
	heading(map_column,"World preview",24)
	preview_view=TextureRect.new();preview_view.custom_minimum_size=Vector2(560,410);preview_view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;preview_view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;preview_view.size_flags_vertical=Control.SIZE_EXPAND_FILL;map_column.add_child(preview_view)
	preview_status=heading(map_column,"Preview terrain, fitted buildings and connected roads before baking.",18);preview_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	preview_button=button(map_column,"Preview world",start_preview)
	seed_field.value_changed.connect(func(_value:float):invalidate_preview())
	ocean.toggled.connect(func(_value:bool):invalidate_preview())
	preset.item_selected.connect(func(_index:int):invalidate_preview())
	button(create,"Create and play",func():launch_selected(true))
	cancel_button=button(create,"Cancel preparation",cancel_preparation);cancel_button.hide()
	gameplay=CheckBox.new();gameplay.text="Gameplay material costs (uncheck for free editor)";gameplay.button_pressed=true;panel.add_child(gameplay)
	notice=heading(panel,"",18);notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;notice.custom_minimum_size.y=54
	button(panel,"Quit",request_quit)
	refresh()
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
		lines.append("Landscape: "+({17:"Regional inland",18:"Regional inland",19:"Regional coast",13:"Earlier regional recipe"}.get(id,Launch.PRESETS.get(id,"Saved recipe "+str(id)))))
	if data.has("settlement_layout"):lines.append("Layout: "+str(data.settlement_layout).capitalize())
	if saved_picture.texture==null:lines.append("No cached photograph yet.")
	lines.append("Opening uses this world's saved generation settings.")
	saved_details.text="\n".join(lines)
func launch_selected(create: bool) -> void:
	if preparation_pid>=0 or photograph_pid>=0:return
	var slot:=name_field.text.strip_edges()
	if not create:
		if worlds.get_selected_items().is_empty():notice.text="Select a saved world first.";return
		slot=str(worlds.get_item_metadata(worlds.get_selected_items()[0]))
	var result:=Launch.command(slot,create,preset.get_selected_id(),int(seed_field.value),gameplay.button_pressed,"user://worlds",ocean.button_pressed,["connected","road","settlement"][layout_preset.selected])
	if not result.ok:notice.text=result.reason;return
	if result.get("prepare",false):
		start_preparation(result,slot);return
	# The browser owns no world worker or canonical save. Launch one world and
	# exit the browser instead of replacing a live world's storage ownership.
	_open_game(result.args)

func start_preparation(result:Dictionary,slot:String)->void:
	preparation_slot=slot;preparation_gameplay=gameplay.button_pressed
	preparation_status="user://world_preparation_%d_%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	preparation_cancel=preparation_status+".cancel";cancel_pending=false
	result.args.append_array(PackedStringArray(["--status-file="+ProjectSettings.globalize_path(preparation_status),"--cancel-file="+ProjectSettings.globalize_path(preparation_cancel)]))
	preparation_pid=OS.create_process(OS.get_executable_path(),result.args,false)
	if preparation_pid<0:notice.text="Could not start the world-generation process.";return
	cancel_button.show();cancel_button.disabled=false
	preparation_started_msec=Time.get_ticks_msec()
	Engine.max_fps=10
	notice.text="Preparing and verifying %s. The preparation window will close when finished, then your world will open. Existing saves are preserved."%slot

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
		if OS.is_process_running(photograph_pid):
			if Time.get_ticks_msec()>photograph_deadline:cancel_photographs();notice.text="Photograph capture timed out. Saved world unchanged."
			return
		var code:=OS.get_process_exit_code(photograph_pid)
		photograph_pid=-1;Engine.max_fps=60;photograph_button.disabled=false;photograph_cancel.hide()
		var log:=FileAccess.get_file_as_string(photograph_log) if FileAccess.file_exists(photograph_log) else ""
		refresh()
		notice.text=("Photographs refreshed for "+photograph_slot+".") if code==0 and "WORLD_PREVIEWS failures=0" in log and not "ERROR:" in log else "Photograph capture failed. Saved world unchanged. Log: "+photograph_log
		return
	if preparation_pid<0:return
	preparation_poll-=delta
	if preparation_poll>0:return
	preparation_poll=0.5
	if OS.is_process_running(preparation_pid):
		_update_preparation_notice();return
	preparation_pid=-1;Engine.max_fps=60;cancel_button.hide()
	var result:Variant=JSON.parse_string(FileAccess.get_file_as_string(preparation_status)) if FileAccess.file_exists(preparation_status) else null
	refresh()
	if quit_pending:get_tree().quit();return
	if cancel_pending:
		notice.text="Preparation cancelled. Existing saves are preserved."
		if result is Dictionary and result.get("state","")=="ready":notice.text="Preparation finished before cancellation. The verified world is saved; select it when ready to play."
		return
	if not result is Dictionary or result.get("state","")!="ready":
		notice.text="World preparation did not finish. Existing saves are preserved. " + (str(result.get("reason",""))+" Logs: "+str(result.get("report","")) if result is Dictionary else "Check the generation report.")
		return
	var launch:=Launch.command(preparation_slot,false,12,0,preparation_gameplay)
	if not launch.ok:notice.text=launch.reason;return
	_open_game(launch.args)

func _open_game(args:PackedStringArray)->void:
	var pid:=OS.create_process(OS.get_executable_path(),args)
	if pid<0:notice.text="Could not start Godot. Select the saved world to try again.";return
	get_tree().quit()

func _update_preparation_notice()->void:
	var result:Variant=JSON.parse_string(FileAccess.get_file_as_string(preparation_status)) if FileAccess.file_exists(preparation_status) else null
	if cancel_pending:
		notice.text="Stopping preparation; waiting for its process to close. Existing saves are preserved.";return
	var stage:="Starting preparation"
	if result is Dictionary:
		match str(result.get("state","")):
			"creating":stage="Generating terrain, locations and saved world"
			"verifying":stage="Reopening the saved world and checking its contents"
			"recovering":stage="Verifying and recovering interrupted publication"
			"publishing":stage="Publishing the verified world"
			"ready":stage="World ready; preparing to open"
			"failed":stage="Preparation failed; collecting the result"
	if result is Dictionary and result.get("progress",{}) is Dictionary:
		var detail:Dictionary=result.get("progress",{})
		if not str(detail.get("stage","")).is_empty():
			stage=str(detail.stage)
			if int(detail.get("total",0))>0:stage+=" · %d / %d"%[int(detail.get("completed",0)),int(detail.total)]
	var elapsed:int=maxi(0,Time.get_ticks_msec()-preparation_started_msec)/1000
	notice.text="%s: %s. Elapsed %d:%02d. Existing saves are preserved."%[preparation_slot,stage,elapsed/60,elapsed%60]

func cancel_preparation()->void:
	if preparation_pid<0 or cancel_pending:return
	var request:=FileAccess.open(preparation_cancel,FileAccess.WRITE)
	if request==null:notice.text="Could not request cancellation. Preparation is still running.";return
	request.store_string("cancel");request.close()
	cancel_pending=true;cancel_button.disabled=true
	_update_preparation_notice()
func request_quit()->void:
	if photograph_pid>=0:cancel_photographs()
	if preparation_pid<0:get_tree().quit();return
	cancel_preparation()
	quit_pending=cancel_pending
func _notification(what:int)->void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:request_quit()

func selected_preview_key()->String:
	return "%d/%d/%d"%[int(seed_field.value),19 if ocean.button_pressed else 17,layout_preset.selected] if preset.get_selected_id()==Launch.INTEGRATED_PRESET else "%d/%d"%[int(seed_field.value),preset.get_selected_id()]
func invalidate_preview()->void:
	preview_view.texture=null
	preview_status.text="Settings changed. Preview the new world plan before creating."
func start_preview()->void:
	if preview_worker!=null:return
	var generator:int=19 if ocean.button_pressed else 17
	if preset.get_selected_id()!=Launch.INTEGRATED_PRESET:generator=preset.get_selected_id()
	if generator>=10000:preview_status.text="Select the current regional world to preview terrain.";return
	preview_key=selected_preview_key();preview_status.text="Planning terrain, settlements and roads…";preview_button.disabled=true
	preview_worker=Thread.new()
	var job:Callable=preload("res://addons/world_runtime/world_generation_plan.gd").preview.bind(int(seed_field.value),generator,preset.get_selected_id()==Launch.INTEGRATED_PRESET,layout_preset.selected==0,layout_preset.selected<2)
	if preview_worker.start(job)!=OK:preview_worker=null;preview_button.disabled=false;preview_status.text="Could not start terrain preview."
func poll_preview()->void:
	if preview_worker==null or preview_worker.is_alive():return
	var result:Dictionary=preview_worker.wait_to_finish();preview_worker=null;preview_button.disabled=false
	if preview_key!=selected_preview_key():return
	if not result.get("ok",false):preview_status.text="Terrain preview failed. No world was created.";return
	preview_view.texture=ImageTexture.create_from_image(Image.create_from_data(256,256,false,Image.FORMAT_RGBA8,result.pixels))
	if result.has("building_count"):
		preview_status.text="World plan · north is up · 2 km × 2 km\n%d buildings · roads in gold · buildings in ivory\n"%int(result.building_count)
		preview_status.text+="The bake reuses this cached placement plan." if result.get("plan_reusable",false) else "Cache unavailable; generation will repeat this deterministic plan."
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
	photograph_pid=OS.create_process(OS.get_executable_path(),args,false)
	if photograph_pid<0:notice.text="Could not start photograph capture.";return
	photograph_deadline=Time.get_ticks_msec()+150000
	Engine.max_fps=10;photograph_button.disabled=true;photograph_cancel.show()
	notice.text="Photographing "+photograph_slot+" in a read-only window. Its saved world will not change."
func cancel_photographs()->void:
	if photograph_pid<0:return
	if OS.is_process_running(photograph_pid):OS.kill(photograph_pid)
	photograph_pid=-1;Engine.max_fps=60;photograph_button.disabled=false;photograph_cancel.hide()
	notice.text="Photograph capture cancelled. Saved world unchanged."
