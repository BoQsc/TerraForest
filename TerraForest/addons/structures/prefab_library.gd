# SPDX-License-Identifier: 0BSD
extends RefCounted
## Infrequent authoring I/O; cell traversal/validation stays in NativeBlockWorld.
const MAX_ASSETS:=32
const MAX_FILE_BYTES:=8*1024*1024
var directory: String="user://building_prefabs"
var assets: Array[Resource]=[]
var _paths: Dictionary={}
var corner_a: Vector3i
var corner_b: Vector3i
var has_a:=false
var has_b:=false

func load_library() -> void:
	assets.clear()
	_paths.clear()
	if not DirAccess.dir_exists_absolute(directory): return
	var names:=DirAccess.get_files_at(directory)
	names.sort()
	for file: String in names:
		if assets.size()>=MAX_ASSETS: break
		if not file.ends_with(".res"): continue
		var path:=directory.path_join(file)
		var asset:=_read_asset(path)
		if asset!=null:
			assets.append(asset)
			_paths[asset.get_instance_id()]=path

func _read_asset(path: String) -> Resource:
	var stream:=FileAccess.open(path,FileAccess.READ)
	if stream==null: return null
	var length:=stream.get_length();stream.close()
	if length<=0 or length>MAX_FILE_BYTES: return null
	var asset:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	return asset if asset!=null and asset.is_class("NativeBlockPrefab") and asset.get_cell_count()>0 else null

func owns(asset: Resource) -> bool:
	return asset!=null and assets.has(asset) and _paths.has(asset.get_instance_id())

func archive(asset: Resource) -> Dictionary:
	if not owns(asset): return {"ok":false,"reason":"Only saved personal prefabs can be archived"}
	var source: String=_paths[asset.get_instance_id()]
	if source.get_base_dir()!=directory: return {"ok":false,"reason":"Prefab does not belong to this library"}
	var folder:=directory.path_join("archive")
	if DirAccess.make_dir_recursive_absolute(folder)!=OK: return {"ok":false,"reason":"Cannot create prefab archive"}
	var target:=folder.path_join("prefab_%020d_%d.res" % [Time.get_unix_time_from_system()*1000000,Time.get_ticks_usec()])
	if FileAccess.file_exists(target): return {"ok":false,"reason":"Archive filename already exists; retry"}
	var error:=DirAccess.rename_absolute(source,target)
	if error!=OK: return {"ok":false,"reason":"Could not archive prefab (%d)" % error}
	assets.erase(asset);_paths.erase(asset.get_instance_id())
	return {"ok":true,"path":target}

func restore_latest() -> Dictionary:
	if assets.size()>=MAX_ASSETS: return {"ok":false,"reason":"Library is full (32 prefabs)"}
	var folder:=directory.path_join("archive")
	if not DirAccess.dir_exists_absolute(folder): return {"ok":false,"reason":"No archived prefabs"}
	var names:=DirAccess.get_files_at(folder);names.sort();names.reverse()
	for file: String in names:
		if not file.ends_with(".res"): continue
		var source:=folder.path_join(file)
		var asset:=_read_asset(source)
		if asset==null: return {"ok":false,"reason":"Archived prefab could not be read; file retained"}
		var target:=directory.path_join(file)
		if FileAccess.file_exists(target): return {"ok":false,"reason":"Restore filename is occupied; files retained"}
		var error:=DirAccess.rename_absolute(source,target)
		if error!=OK: return {"ok":false,"reason":"Could not restore prefab (%d)" % error}
		assets.append(asset);_paths[asset.get_instance_id()]=target
		return {"ok":true,"asset":asset,"path":target}
	return {"ok":false,"reason":"No archived prefabs"}

func select_corner(first: bool,cell: Vector3i) -> void:
	if first: corner_a=cell;has_a=true
	else: corner_b=cell;has_b=true

func selection_text() -> String:
	if not has_a or not has_b: return "A: %s   B: %s" % [str(corner_a) if has_a else "unset",str(corner_b) if has_b else "unset"]
	return "Selection: %s cells%s" % [str((corner_b-corner_a).abs()+Vector3i.ONE),"" if selection_within_limit() else " · exceeds capture limit"]

func clear_selection() -> void:
	has_a=false;has_b=false

func selection_within_limit() -> bool:
	if not has_a or not has_b: return false
	var size: Vector3i=(corner_b-corner_a).abs()+Vector3i.ONE
	return size.x<=256 and size.y<=256 and size.z<=256 and size.x*size.y*size.z<=262144

func capture(blocks: Object,title: String) -> Dictionary:
	if not has_a or not has_b: return {"ok":false,"reason":"Choose both corners first"}
	title=title.strip_edges()
	if title.is_empty() or title.length()>48: return {"ok":false,"reason":"Use a name of 1–48 characters"}
	if assets.size()>=MAX_ASSETS: return {"ok":false,"reason":"Library is full (32 prefabs)"}
	var origin:=corner_a.min(corner_b)
	var size: Vector3i=(corner_b-corner_a).abs()+Vector3i.ONE
	var asset: Resource=blocks.capture_prefab(origin,size)
	if asset==null or asset.get_cell_count()==0: return {"ok":false,"reason":"Selection is empty, too large, or not fully loaded"}
	return _save_asset(asset,title)

func stack(source: Resource,count: int,title: String) -> Dictionary:
	title=title.strip_edges()
	if title.is_empty() or title.length()>48: return {"ok":false,"reason":"Use a name of 1–48 characters"}
	if assets.size()>=MAX_ASSETS: return {"ok":false,"reason":"Library is full (32 prefabs)"}
	if source==null or not source.is_class("NativeBlockPrefab") or source.get_cell_count()==0 or count<2 or count>32:
		return {"ok":false,"reason":"Select a nonempty prefab and 2–32 repeats"}
	var placements:=PackedInt32Array()
	var height: int=ceili(source.get_bounds().size.y)
	if source.has_meta("stack_height"):
		var spacing: Variant=source.get_meta("stack_height")
		if typeof(spacing)!=TYPE_INT or spacing<1 or spacing>4095:
			return {"ok":false,"reason":"Prefab has invalid stack spacing"}
		height=spacing
	for level in count: placements.append_array(PackedInt32Array([0,0,level*height,0,0]))
	var asset: Resource=ClassDB.instantiate("NativeBlockPrefab")
	if not asset.compose([source],placements): return {"ok":false,"reason":"Assembly exceeds prefab cell or coordinate limits"}
	if source.has_meta("stack_height"): asset.set_meta("stack_height",height*count)
	return _save_asset(asset,title)

func _save_asset(asset: Resource,title: String) -> Dictionary:
	asset.resource_name=title
	var error:=DirAccess.make_dir_recursive_absolute(directory)
	if error!=OK: return {"ok":false,"reason":"Cannot create prefab library"}
	# A new filename per capture avoids overwriting another authored asset.
	var path:=directory.path_join("prefab_%d_%d.res" % [Time.get_unix_time_from_system()*1000000,Time.get_ticks_usec()])
	if FileAccess.file_exists(path): return {"ok":false,"reason":"Prefab filename already exists; retry"}
	error=ResourceSaver.save(asset,path)
	if error!=OK: return {"ok":false,"reason":"Could not save prefab (%d)" % error}
	assets.append(asset)
	_paths[asset.get_instance_id()]=path
	return {"ok":true,"asset":asset,"path":path}
