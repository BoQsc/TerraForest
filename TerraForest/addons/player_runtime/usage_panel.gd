extends VBoxContainer
const POLICY="res://addons/world_runtime/resource_budgets.json"
var budgets:Dictionary={}
var paths:Dictionary={}
var folder_buttons:Dictionary={}
var meters:Dictionary={}
var probe:RefCounted
var active:=false
var notice:Label
var live_note:Label
var active_cache_button:Button
var opener:Callable
var live:Dictionary={}
var live_samples:=0
var live_clock:=0.0

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
			var pack:=ProjectSettings.globalize_path(arguments[index+1]).simplify_path();content_root=pack.get_base_dir()
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
	var data_button:=Button.new();data_button.text="Open game data";data_button.tooltip_text=paths.data;data_button.pressed.connect(open_folder.bind("data"));actions.add_child(data_button)
	active_cache_button=Button.new();active_cache_button.text="Open active cache";active_cache_button.tooltip_text=paths.active_cache;active_cache_button.disabled=not DirAccess.dir_exists_absolute(paths.active_cache);active_cache_button.pressed.connect(open_folder.bind("active_cache"));actions.add_child(active_cache_button)
	text("Open a folder to inspect its contents. No folder-size scans run here.",13)
	for entry:Array in [["content","Game content"],["worlds","Worlds + backups"],["cache","Terrain mesh caches"],["logs","Game logs"],["reports","Developer reports"],["build","Compiler / test builds"],["imports","Godot import cache"],["history","Git history"]]:
		var key:String=entry[0]
		if not paths.has(key):continue
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);add_child(row)
		var title:=Label.new();title.text=entry[1];title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(title)
		var button:=Button.new();button.text="Open folder";button.custom_minimum_size=Vector2(110,34);button.tooltip_text=paths[key];button.disabled=not DirAccess.dir_exists_absolute(paths[key]);button.pressed.connect(open_folder.bind(key));row.add_child(button);folder_buttons[key]=button
	text("Storage policies",20)
	if not budgets.is_empty():
		text("Game content: %s target · warning %s\nTerrain cache: %s maintenance quota · failed test caches: %s retention quota\nWorlds + backups: warn at %s; never auto-delete or refuse a save\nSuccessful temporary-check caches are removed by the shared test runner.\nDisk reserve for automated checks: %s. RAM limits are provisional."%[size_text(int(budgets.redistributable_limit_bytes),true),size_text(int(budgets.redistributable_warning_bytes),true),size_text(int(budgets.derived_cache_total_bytes)),size_text(int(budgets.failed_test_cache_bytes)),size_text(int(budgets.saved_world_warning_bytes)),size_text(int(budgets.minimum_free_bytes))],14)
	else:text("Budget data is unavailable. Re-export the game to include its shared resource policy.")
	text("Storage limits are policies, not measured folder totals. Developer folders are not shipped game content.",13)
	notice=text("",14)

func set_active(value:bool)->void:
	if active==value:return
	active=value;set_process(value)
	if not value:return
	if probe==null and ClassDB.class_exists("NativeResourceUsage"):probe=ClassDB.instantiate("NativeResourceUsage")
	for key:String in folder_buttons:folder_buttons[key].disabled=not DirAccess.dir_exists_absolute(paths[key])
	active_cache_button.disabled=not DirAccess.dir_exists_absolute(paths.active_cache)
	refresh_live();live_clock=0

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

func open_folder(key:String)->Error:
	if not paths.has(key):return ERR_INVALID_PARAMETER
	var path:String=paths[key]
	if not DirAccess.dir_exists_absolute(path):notice.text="This folder is not present: "+path;return ERR_DOES_NOT_EXIST
	var result:Error=opener.call(path) if opener.is_valid() else OS.shell_open(path)
	notice.text="Opened in your file manager: "+path if result==OK else "Could not open this folder (error %d)."%result
	return result

func _process(delta:float)->void:
	live_clock+=delta
	if live_clock>=1.0:live_clock=0;refresh_live()
