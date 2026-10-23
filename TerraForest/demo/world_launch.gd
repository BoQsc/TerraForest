# SPDX-License-Identifier: 0BSD
extends RefCounted
const INTEGRATED_PRESET:=10019
const LEGACY_INTEGRATED_PRESET:=10012
const PRESETS={10019:"Terrain-fitted regional world",10012:"Earlier five-site regional recipe",1:"Original woodland",4:"Mountains, caves, ore veins and lakes",6:"Accessible cave entrances, ore veins and lakes",7:"Regional roads and settlement ground (in development)",8:"Regional world with domed cave chambers",9:"Regional world with connected cave floors",10:"Provisional mine layout",11:"Regional world with owned mine (in development)",12:"Regional world with larger lake (in development)"}
static func engine_prefix()->PackedStringArray:
	var arguments:=OS.get_cmdline_args()
	if ClassDB.class_exists("NativeWorldArchive"):
		var runtime=ClassDB.instantiate("NativeWorldArchive")
		if runtime.has_method("process_arguments"):arguments=runtime.process_arguments()
	return engine_prefix_for(arguments,ProjectSettings.globalize_path("res://"))
static func engine_prefix_for(arguments:PackedStringArray,source_folder:String)->PackedStringArray:
	# Explicit pack launches also work when the engine executable lives elsewhere.
	# Preserve the same pack for every child instead of assuming an adjacent PCK.
	var pack:=""
	for i in arguments.size():
		if arguments[i]=="--":break
		if arguments[i]=="--main-pack" and i+1<arguments.size():pack=arguments[i+1]
		elif arguments[i].begins_with("--main-pack="):pack=arguments[i].trim_prefix("--main-pack=")
	if not pack.is_empty():
		if not pack.is_absolute_path():
			var current:=DirAccess.open(".")
			if current!=null:pack=current.get_current_dir().path_join(pack).simplify_path()
		return PackedStringArray(["--main-pack",pack])
	# A native exported executable discovers an adjacent PCK without extra flags.
	return PackedStringArray(["--path",source_folder]) if not source_folder.is_empty() else PackedStringArray()
static func valid_slot(slot: String) -> bool:
	var pattern:=RegEx.new();pattern.compile("^[A-Za-z_][A-Za-z0-9_]{0,47}$")
	return pattern.search(slot)!=null
const NAME_FIRST=["Amber","Autumn","Blue","Bright","Calm","Cedar","Copper","Crystal","Emerald","Golden","Hidden","Misty","Mossy","Quiet","Silver","Wild"]
const NAME_SECOND=["Bay","Brook","Coast","Creek","Fields","Forest","Glen","Grove","Haven","Hills","Hollow","Meadow","Pines","Ridge","Vale","Woods"]
static func unique_world_name(base:String,directory:String="user://worlds")->String:
	# Include partial worlds and locks, and avoid Windows case aliases. No writes.
	var occupied:Dictionary={}
	var folder:=DirAccess.open(directory)
	if folder!=null:
		for entry:String in folder.get_files()+folder.get_directories():
			occupied[entry.get_slice(".",0).to_lower()]=true
	var candidate:=base
	var suffix:=2
	while occupied.has(candidate.to_lower()):
		candidate=base+"_"+str(suffix);suffix+=1
	return candidate
static func generated_world_name(directory:String="user://worlds")->String:
	# Naming has its own RNG; it must not change the terrain seed/random stream.
	var random:=RandomNumberGenerator.new();random.randomize()
	var base:String=NAME_FIRST[random.randi_range(0,NAME_FIRST.size()-1)]+"_"+NAME_SECOND[random.randi_range(0,NAME_SECOND.size()-1)]
	return unique_world_name(base,directory)
static func preparation_slot(slot:String)->bool:
	var pattern:=RegEx.new();pattern.compile("^combined_stage_[0-9a-f]{32}$")
	return pattern.search(slot)!=null
static func saved_slots(directory: String="user://worlds",include_preparation:bool=false,order:String="played") -> PackedStringArray:
	var slots:=PackedStringArray();var folder:=DirAccess.open(directory)
	if folder==null:return slots
	for file in folder.get_files():
		if file.ends_with(".trw") and valid_slot(file.trim_suffix(".trw")) and (include_preparation or not preparation_slot(file.trim_suffix(".trw"))):slots.append(file.trim_suffix(".trw"))
	var rows:Array=[]
	for slot:String in slots:
		var path:=directory.path_join(slot+".trw")
		var data:Dictionary=preload("res://addons/world_runtime/world_presentation.gd").metadata(slot,directory)
		rows.append({"slot":slot,"time":int(data.get("last_played",0)) if order=="played" else int(data.get("created",0)),"saved":FileAccess.get_modified_time(path)})
	rows.sort_custom(func(a:Dictionary,b:Dictionary):
		if order=="name":return a.slot.naturalnocasecmp_to(b.slot)<0
		if a.time!=b.time:return a.time>b.time
		if a.saved!=b.saved:return a.saved>b.saved
		return a.slot.naturalnocasecmp_to(b.slot)<0)
	slots.clear()
	for row:Dictionary in rows:slots.append(row.slot)
	return slots
static func command(slot: String,create: bool,generator: int,seed: int,gameplay: bool,directory: String="user://worlds",ocean:bool=true,layout:String="connected") -> Dictionary:
	if not valid_slot(slot):return {"ok":false,"reason":"Use 1–48 letters, digits or underscores; start with a letter or underscore."}
	var canonical:=directory.path_join(slot+".trw")
	if create:
		if preparation_slot(slot):return {"ok":false,"reason":"That name is reserved for preparation. Choose a different world name."}
		if not PRESETS.has(generator) or seed<0 or seed>2147483647 or layout not in ["connected","road","settlement"]:return {"ok":false,"reason":"Choose a generator and seed between 0 and 2147483647."}
		for suffix in ["",".bak",".tmp",".regions",".models",".water",".terrain"]:
			if FileAccess.file_exists(canonical+suffix) or DirAccess.dir_exists_absolute(canonical+suffix):return {"ok":false,"reason":"That name already has world data. Choose another name or open the saved world."}
		if FileAccess.file_exists(directory.path_join(slot+".clone.lock")):return {"ok":false,"reason":"That world is being prepared. Choose another name."}
		# Native leases are owned by an OS handle, not by the presence of a file.
		# A process crash can leave the file but must not permanently reserve a name.
		if FileAccess.file_exists(directory.path_join(slot+".prepare.lock")):
			var lease=ClassDB.instantiate("NativeWorldArchive")
			if not lease.acquire(ProjectSettings.globalize_path(directory.path_join(slot+".prepare"))):return {"ok":false,"reason":"That world is being prepared. Choose another name."}
			lease.release()
	elif not FileAccess.file_exists(canonical):return {"ok":false,"reason":"The selected save is no longer available. Refresh the list."}
	if create and generator in [INTEGRATED_PRESET,LEGACY_INTEGRATED_PRESET]:
		var actual_generator:int=(19 if ocean else 17) if generator==INTEGRATED_PRESET else 13
		var preparation:=engine_prefix()+PackedStringArray(["--headless","--script","res://addons/world_runtime/generation_job.gd","--","--destination="+slot,"--seed="+str(seed),"--generator="+str(actual_generator),"--settlement-layout="+layout])
		return {"ok":true,"prepare":true,"args":preparation}

	var args:=engine_prefix()+PackedStringArray(["--fullscreen","--resolution","1920x1080","--max-fps","60","res://demo/world.tscn","--","--world-slot="+slot,"--ground-cover","--actors","--vehicle-fleet","--max-fps=60"])
	if create:args.append_array(PackedStringArray(["--world-generator="+str(generator),"--world-seed="+str(seed)]))
	if preparation_slot(slot):args.append("--snapshot-readonly")
	if gameplay:args.append("--gameplay-construction")
	return {"ok":true,"args":args}

static func recovery_command(slot:String)->Dictionary:
	if not valid_slot(slot) or preparation_slot(slot):return {"ok":false,"reason":"Enter the original world name using letters, digits and underscores."}
	if FileAccess.file_exists("user://worlds/"+slot+".trw"):return {"ok":false,"reason":"This world is already published. Open it from My worlds."}
	return {"ok":true,"prepare":true,"args":engine_prefix()+PackedStringArray(["--headless","--script","res://addons/world_runtime/generation_job.gd","--","--destination="+slot,"--recover-publication"])}

static func photograph_command(slot:String,directory:String="user://worlds")->Dictionary:
	if not valid_slot(slot) or preparation_slot(slot) or not FileAccess.file_exists(directory.path_join(slot+".trw")):return {"ok":false,"reason":"Select a published saved world first."}
	return {"ok":true,"args":engine_prefix()+PackedStringArray(["--fullscreen","--resolution","1920x1080","--max-fps","60","--script","res://addons/world_runtime/capture_world_previews.gd","--","--snapshot-readonly","--temporary","--world-slot="+slot,"--ground-cover"])}
