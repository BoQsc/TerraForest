extends VBoxContainer
const POLICY="res://addons/world_runtime/resource_budgets.json"
var snapshot_path:="user://usage_sizes_v1.json"
var cached_sizes:Dictionary={}
var cache_loaded:=false
var scan_polling:=false
var terrain_source:Variant
var folder_refresh:Dictionary={}
var recorded_rows:Dictionary={}
var snapshot_dirty:=false
var budgets:Dictionary={}
var paths:Dictionary={}
var folder_labels:Dictionary={}
var folder_buttons:Dictionary={}
var meters:Dictionary={}
var locations:Array[Dictionary]=[]
var probe:RefCounted
var active:=false
var scan_started:=false
var scan_button:Button
var scan_note:Label
var notice:Label
var live_note:Label
var active_cache_button:Button
var opener:Callable
var live:Dictionary={}
var scan:Dictionary={}
var live_samples:=0
var live_clock:=0.0
var scan_clock:=0.0
var pack_file:="TerraForest.pck"

static func size_text(bytes:int,decimal:bool=false)->String:
	if bytes<0:return "Unavailable"
	var base:=1000.0 if decimal else 1024.0
	var units:PackedStringArray=["B","kB","MB","GB"] if decimal else ["B","KiB","MiB","GiB"]
	var value:=float(bytes);var unit:=0
	while value>=base and unit<3:value/=base;unit+=1
	return ("%.2f %s" if unit==3 else "%.0f %s")%[value,units[unit]]

func text(value:String,font_size:int=16)->Label:
	var out:=Label.new();out.text=value;out.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;out.add_theme_font_size_override("font_size",font_size);add_child(out);return out

func resolve_paths(host:Node)->void:
	var resource_root:=ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	var content_root:=resource_root
	if content_root.is_empty():content_root=DirAccess.open(".").get_current_dir().simplify_path()
	var arguments:=OS.get_cmdline_args()
	for index:int in arguments.size():
		if arguments[index]=="--main-pack" and index+1<arguments.size():
			var pack:=ProjectSettings.globalize_path(arguments[index+1]).simplify_path();content_root=pack.get_base_dir();pack_file=pack.get_file()
	var development:=""
	for candidate:String in [resource_root,content_root.get_base_dir()]:
		if FileAccess.file_exists(candidate.path_join("project.godot")) and DirAccess.dir_exists_absolute(candidate.path_join("demo")):development=candidate;break
	if not development.is_empty() and content_root==development:content_root=development.path_join("dist")
	paths={"data":OS.get_user_data_dir(),"content":content_root,"worlds":OS.get_user_data_dir().path_join("worlds"),"cache":OS.get_user_data_dir(),"logs":OS.get_user_data_dir().path_join("logs")}
	paths["active_cache"]=ProjectSettings.globalize_path(host.terrain.backend.cache_path).simplify_path()
	if not development.is_empty():
		paths.merge({"reports":development.path_join("reports"),"build":development.path_join(".build"),"imports":development.path_join(".godot/imported")})
		var history:=development.get_base_dir().path_join(".git")
		if DirAccess.dir_exists_absolute(history):paths["history"]=history

func build(host:Node)->void:
	set_process(false);add_theme_constant_override("separation",10)
	terrain_source=host.terrain
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(POLICY))
	if parsed is Dictionary:budgets=parsed
	resolve_paths(host)
	text("Usage",24)
	text("Live measurements while this page is open. Targets flag regressions; they are not allocator caps or certified minimum specifications.",14)
	for key:String in ["ram","gpu","free"]:
		var line:=Label.new();line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(line)
		var bar:=ProgressBar.new();bar.show_percentage=false;bar.custom_minimum_size.y=7;bar.max_value=1;add_child(bar)
		meters[key]={"label":line,"bar":bar}
	live_note=text("",13)
	text("Storage folders",20)
	var actions:=HBoxContainer.new();add_child(actions)
	scan_button=Button.new();scan_button.text="Refresh sizes · 8s budget";scan_button.pressed.connect(start_scan);actions.add_child(scan_button)
	var data_button:=Button.new();data_button.text="Open game data";data_button.tooltip_text=paths.data;data_button.pressed.connect(open_folder.bind("data"));actions.add_child(data_button)
	active_cache_button=Button.new();active_cache_button.text="Open active cache";active_cache_button.tooltip_text=paths.active_cache;active_cache_button.disabled=not DirAccess.dir_exists_absolute(paths.active_cache);active_cache_button.pressed.connect(open_folder.bind("active_cache"));actions.add_child(active_cache_button)
	scan_note=text("Saved readings appear immediately. Use ↻ to refresh one folder; opening Usage does not recount files.",13)
	for entry:Array in [["content","Game content",1],["worlds","Worlds + backups",0],["cache","Terrain mesh caches",2],["logs","Game logs",0],["reports","Developer reports",0],["build","Compiler / test builds",0],["imports","Godot import cache",0],["history","Git history",0]]:
		var key:String=entry[0]
		if not paths.has(key):continue
		locations.append({"id":key,"path":paths[key],"mode":entry[2],"pack_file":pack_file})
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);add_child(row)
		var title:=Label.new();title.text=entry[1];title.custom_minimum_size.x=195;row.add_child(title)
		var value:=Label.new();value.text="Not measured";value.size_flags_horizontal=Control.SIZE_EXPAND_FILL;value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;row.add_child(value);folder_labels[key]=value
		var refresh:=Button.new();refresh.text="↻";refresh.custom_minimum_size=Vector2(34,34);refresh.tooltip_text="Refresh only this folder · up to eight seconds of discovery";refresh.pressed.connect(start_scan.bind(key));row.add_child(refresh);folder_refresh[key]=refresh
		var button:=Button.new();button.text="Open folder";button.custom_minimum_size=Vector2(110,34);button.tooltip_text=paths[key];button.disabled=not DirAccess.dir_exists_absolute(paths[key]);button.pressed.connect(open_folder.bind(key));row.add_child(button);folder_buttons[key]=button
	text("Storage policies",20)
	if not budgets.is_empty():
		text("Game content: %s target · warning %s\nTerrain cache: %s maintenance quota · failed test caches: %s retention quota\nWorlds + backups: warn at %s; never auto-delete or refuse a save\nSuccessful temporary-check caches are removed by the shared test runner.\nDisk reserve for automated checks: %s. RAM limits are provisional."%[size_text(int(budgets.redistributable_limit_bytes),true),size_text(int(budgets.redistributable_warning_bytes),true),size_text(int(budgets.derived_cache_total_bytes)),size_text(int(budgets.failed_test_cache_bytes)),size_text(int(budgets.saved_world_warning_bytes)),size_text(int(budgets.minimum_free_bytes))],14)
	else:text("Budget data is unavailable. Re-export the game to include its shared resource policy.")
	text("Folder figures are timestamped snapshots, not live filesystem totals. Active-cache accounting is read from the terrain worker. Cache estimates are not safe-deletion audits; links are skipped.",13)
	notice=text("",14)

func set_active(value:bool)->void:
	if active==value:return
	active=value;set_process(value)
	if not value:
		if probe!=null:probe.cancel_scan()
		save_sizes()
		return
	if probe==null and ClassDB.class_exists("NativeResourceUsage"):probe=ClassDB.instantiate("NativeResourceUsage")
	for key:String in folder_buttons:folder_buttons[key].disabled=not DirAccess.dir_exists_absolute(paths[key])
	active_cache_button.disabled=not DirAccess.dir_exists_absolute(paths.active_cache)
	if not cache_loaded:load_sizes();cache_loaded=true
	refresh_live();live_clock=0;scan_clock=0
	if scan_started:refresh_scan()
	else:render_sizes()

func load_sizes()->void:
	if not snapshot_path.is_empty() and FileAccess.file_exists(snapshot_path):
		var file:=FileAccess.open(snapshot_path,FileAccess.READ)
		if file!=null and file.get_length()<=65536:
			var parsed:Variant=JSON.parse_string(file.get_as_text())
			if parsed is Dictionary and parsed.get("schema")==1 and parsed.get("records") is Dictionary:
				for entry:Dictionary in locations:
					var record:Variant=parsed.records.get(entry.id)
					if record is Dictionary and record.get("path")==entry.path and record.get("mode")==entry.mode and float(record.get("bytes",-1))>=0 and float(record.get("measured_at",0))>0:cached_sizes[entry.id]=record
	var metadata:String=paths.content.path_join("usage_content.json")
	if FileAccess.file_exists(metadata):
		var file:=FileAccess.open(metadata,FileAccess.READ)
		if file!=null and file.get_length()<=4096:
			var parsed:Variant=JSON.parse_string(file.get_as_text())
			var pack:=FileAccess.open(paths.content.path_join(pack_file),FileAccess.READ)
			if parsed is Dictionary and parsed.get("schema")==1 and pack!=null and int(parsed.get("pack_bytes",-1))==pack.get_length() and float(parsed.get("bytes",-1))>=0 and float(parsed.get("measured_at",0))>0:
				cached_sizes.content={"path":paths.content,"mode":1,"bytes":int(parsed.bytes),"measured_at":parsed.measured_at,"source":"export metadata"}

func save_sizes()->void:
	if snapshot_path.is_empty() or not snapshot_dirty:return
	var temporary:=snapshot_path+".tmp"
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return
	file.store_string(JSON.stringify({"schema":1,"records":cached_sizes}));file.flush();var valid:=file.get_error()==OK;file.close()
	if valid and DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(snapshot_path))==OK:snapshot_dirty=false

func meter(key:String,title:String,value:int,limit:int,warning:int,peak:int=-1,decimal:bool=false)->void:
	var label:Label=meters[key].label;var bar:ProgressBar=meters[key].bar
	label.text=title+": "+size_text(value,decimal)+( " / "+size_text(limit,decimal) if limit>0 else "")
	if peak>=0:label.text+=" · peak "+size_text(peak,decimal)
	if warning>0:label.text+=" · warn "+size_text(warning,decimal)
	var used:=maxi(value,peak);var colour:=Color("8daca8") if value<0 else Color("8dd8b0")
	if value>=0 and warning>0 and used>=warning:colour=Color("e4bc6b")
	if value>=0 and limit>0 and used>limit:colour=Color("ed8f83")
	label.modulate=colour;bar.modulate=colour;bar.value=clampf(float(value)/maxi(1,limit),0,1) if value>=0 and limit>0 else 0.0

func refresh_live()->void:
	if probe==null or budgets.is_empty():live_note.text="Native process measurements are unavailable in this build.";return
	live=probe.sample(paths.data);live_samples+=1
	meter("ram","RAM · private commit",int(live.get("private_bytes",-1)),int(budgets.ram_limit_bytes),int(budgets.ram_warning_bytes),int(live.get("private_peak_bytes",-1)))
	meter("gpu","GPU · process allocations",int(live.get("gpu_bytes",-1)),int(budgets.vram_limit_bytes),int(budgets.vram_warning_bytes))
	var free:int=live.get("disk_free_bytes",-1)
	meters.free.label.text="Free storage · game-data drive: %s · keep at least %s"%[size_text(free),size_text(int(budgets.minimum_free_bytes))]
	meters.free.label.modulate=Color("ed8f83") if free>=0 and free<int(budgets.minimum_free_bytes) else Color("8daca8")
	meters.free.bar.visible=false
	live_note.text="Resident RAM: %s. Process counters, not whole-device usage. GPU sampling runs only while Usage is visible."%size_text(int(live.get("working_bytes",-1)))
	if terrain_source is Object:
		var accounting:Variant=terrain_source.get("derived_metrics")
		if accounting is Dictionary and accounting.get("enabled",false):
			live_note.text+="\nActive terrain cache: "+(size_text(int(accounting.disk_bytes))+" · existing write/delete accounting" if accounting.get("accounting_complete",false) else "existing accounting pending")

func start_scan(key:String="")->void:
	if probe==null:scan_note.text="Folder measurement is unavailable in this build.";return
	var requested:Array=locations.filter(func(entry:Dictionary)->bool:return key.is_empty() or entry.id==key)
	var order:={"worlds":8,"cache":9}
	requested.sort_custom(func(first:Dictionary,second:Dictionary)->bool:return order.get(first.id,0)<order.get(second.id,0))
	if not probe.start_scan(requested,8000):scan_note.text="The previous refresh is stopping. Try again in a moment.";return
	recorded_rows.clear();scan_started=true;scan_polling=true;scan_button.disabled=true;scan_note.text="Refreshing selected folder metadata…";refresh_scan()

func refresh_scan()->void:
	scan=probe.scan_status();scan_polling=scan.running
	var incomplete:=false
	for row:Dictionary in scan.areas:
		if not row.complete or not row.available:incomplete=true
		if row.complete and row.available and not recorded_rows.has(row.id):
			cached_sizes[row.id]={"path":paths[row.id],"mode":1 if row.id=="content" else 2 if row.id=="cache" else 0,"bytes":int(row.bytes),"files":row.files,"links":row.links,"measured_at":Time.get_unix_time_from_system(),"source":"measured metadata"};recorded_rows[row.id]=true;snapshot_dirty=true
	render_sizes()
	scan_button.disabled=scan.running
	for button:Button in folder_refresh.values():button.disabled=scan.running
	if scan.running:scan_note.text="Refreshing metadata · %.1f / 8 seconds. Saved readings stay visible."%(float(scan.elapsed_ms)/1000.0)
	else:
		save_sizes()
		scan_note.text="Eight-second budget reached: incomplete readings stay marked; saved totals are not replaced by partial counts." if scan.get("timed_out",false) else "Refresh stopped; saved complete readings retained." if scan.cancelled else "Some locations are incomplete; complete saved readings are retained." if incomplete else "Saved readings ready. Opening Usage reuses them without recounting."

func render_sizes()->void:
	var updates:Dictionary={}
	for row:Dictionary in scan.get("areas",[]):updates[row.id]=row
	for key:String in folder_labels:
		var label:Label=folder_labels[key];var record:Dictionary=cached_sizes.get(key,{})
		var row:Dictionary=updates.get(key,{})
		var value:=int(record.get("bytes",-1));var suffix:=" · cached" if value>=0 else ""
		if not row.is_empty() and row.started and not row.available:suffix+=" · unavailable"
		if not row.is_empty() and row.started and not row.complete:
			if value<0 and row.available:value=int(row.bytes)
			suffix+=" · refreshing" if scan.get("running",false) else " · incomplete"
		var limit:=-1;var warning:=-1;var decimal:=key=="content"
		if not budgets.is_empty():
			if key=="content":limit=int(budgets.redistributable_limit_bytes);warning=int(budgets.redistributable_warning_bytes)
			if key=="worlds":warning=int(budgets.saved_world_warning_bytes)
			if key=="cache":limit=int(budgets.derived_cache_total_bytes)
		label.text=(size_text(value,decimal) if value>=0 else "Not measured")+( " / "+size_text(limit,decimal) if limit>0 else "")+suffix
		label.modulate=Color("ed8f83") if limit>0 and value>limit else Color("e4bc6b") if warning>0 and value>=warning else Color.WHITE
		label.tooltip_text=paths[key]
		if not record.is_empty():label.tooltip_text+="\nMeasured: "+Time.get_datetime_string_from_unix_time(int(record.measured_at))+" UTC · "+str(record.get("source","saved measurement"))

func open_folder(key:String)->Error:
	if not paths.has(key):return ERR_INVALID_PARAMETER
	var path:String=paths[key]
	if not DirAccess.dir_exists_absolute(path):notice.text="This folder is not present: "+path;return ERR_DOES_NOT_EXIST
	var result:Error=opener.call(path) if opener.is_valid() else OS.shell_open(path)
	notice.text="Opened in your file manager: "+path if result==OK else "Could not open this folder (error %d)."%result
	return result

func _process(delta:float)->void:
	live_clock+=delta;scan_clock+=delta
	if live_clock>=1.0:live_clock=0;refresh_live()
	if probe!=null and scan_polling and scan_clock>=0.25:scan_clock=0;refresh_scan()

func _exit_tree()->void:
	if probe!=null:probe.cancel_scan()
	save_sizes()
