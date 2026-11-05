# SPDX-License-Identifier: 0BSD
extends RefCounted
const DEFAULT=preload("res://addons/ui_sets/sets/shipped/set.tres")
const ROLES:={"browser_view":"RefCounted","creation_view":"RefCounted","loading_panel":"PanelContainer","loading_background":"Control","loading_details":"Control"}
const ROOTS:=["res://addons/ui_sets/sets","res://ui_sets","user://ui_sets"]
static var preference_path:="user://ui_sets.cfg"
static var session_id:=""
static var diagnostics:=PackedStringArray()
static func discover(roots:Array=ROOTS)->Dictionary:
	var result:Dictionary={};diagnostics.clear()
	for folder:String in roots:_scan(folder,result,0)
	return result
static func _scan(folder:String,result:Dictionary,depth:int)->void:
	if depth>4:return
	var directory:=DirAccess.open(folder)
	if directory==null:return
	var files:=directory.get_files();files.sort();var visited:Dictionary={}
	for name:String in files:
		name=name.trim_suffix(".remap")
		if name!="set.tres":continue
		if visited.has(name):continue
		visited[name]=true
		var value:Resource=load(folder.path_join(name))
		var error:=validate(value,false)
		if not error.is_empty():diagnostics.append(folder+": "+error);continue
		if result.has(value.id):diagnostics.append("Duplicate UI set: "+value.id);continue
		result[value.id]=value
	var children:=directory.get_directories();children.sort()
	for name:String in children:
		if not name.begins_with("."):_scan(folder.path_join(name),result,depth+1)
static func resolve(value:Resource)->Resource:
	if value==null:return null
	var copy:Resource=value.duplicate();var cursor:Resource=value.base
	var visited:Array=[value]
	while cursor!=null:
		if cursor.get_script()!=preload("res://addons/ui_sets/ui_set.gd"):return null
		if visited.has(cursor) or visited.size()>=8:return null
		visited.append(cursor)
		for role:String in ROLES:
			if copy.get(role)==null:copy.set(role,cursor.get(role))
		if copy.runtime_preview==null:copy.runtime_preview=cursor.runtime_preview
		if copy.runtime_preview_pages.is_empty():copy.runtime_preview_pages=cursor.runtime_preview_pages
		cursor=cursor.base
	return copy
static func validate(value:Resource,runtime:bool)->String:
	if value==null or value.get_script()!=preload("res://addons/ui_sets/ui_set.gd"):return "Not a UI set resource"
	if value.schema!=1 or value.id.is_empty() or value.title.is_empty():return "Missing identity or unsupported schema"
	var pattern:=RegEx.new();pattern.compile("^[a-z][a-z0-9_]{0,47}$")
	if pattern.search(value.id)==null:return "Invalid set ID"
	if value.preview==null:return "Missing preview scene"
	if value.preview_pages.is_empty() or value.preview_pages.size()>16:return "Declare one to sixteen preview pages"
	if value.preview_size.x<320 or value.preview_size.y<180 or value.preview_size.x>3840 or value.preview_size.y>2160:return "Unsupported preview size"
	var resolved:=resolve(value)
	if resolved==null:return "Cyclic or excessive inheritance"
	if not runtime:return ""
	if not value.runtime_enabled:return "Reference mockup only; add live adapters before activation"
	if resolved.runtime_preview==null:return "Missing runtime preview adapter"
	if resolved.runtime_preview_pages.is_empty() or resolved.runtime_preview_pages.size()>16:return "Declare runtime preview pages"
	for role:String in ROLES:
		var script:Script=resolved.get(role)
		if script==null or not script.can_instantiate() or script.get_instance_base_type()!=ROLES[role]:return "Invalid adapter: "+role
		if role in ["browser_view","creation_view"]:
			var found:=false
			for method:Dictionary in script.get_script_method_list():
				if method.name=="build" and (int(method.flags)&METHOD_FLAG_STATIC)!=0 and method.args.size()==(1 if role=="browser_view" else 2):found=true
			if not found:return "Missing build method: "+role
		var required:Array=["reset","show_progress","show_work","show_idle","stop_timer","timing_snapshot","set_compact_width"] if role=="loading_panel" else ["reset","observe","refresh"] if role=="loading_details" else []
		var methods:Array=[]
		for method:Dictionary in script.get_script_method_list():methods.append(method.name)
		for method:String in required:
			if not methods.has(method):return "Missing "+method+" in "+role
		var fields:Array=["title","detail","bar","action","work","embedded","preferences_path"] if role=="loading_panel" else ["provider","context"] if role=="loading_details" else ["picture"] if role=="loading_background" else []
		var properties:Array=[]
		for property:Dictionary in script.get_script_property_list():properties.append(property.name)
		for field:String in fields:
			if not properties.has(field):return "Missing "+field+" in "+role
	return ""
static func selected_id()->String:
	if not session_id.is_empty():return session_id
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-set="):return arg.trim_prefix("--ui-set=")
	var settings:=ConfigFile.new()
	return str(settings.get_value("world_screens","active","shipped")) if settings.load(preference_path)==OK else "shipped"
static func active()->Resource:
	var sets:=discover();var selected:String=selected_id()
	var value:Resource=sets.get(selected,DEFAULT)
	var error:=validate(value,true)
	if not error.is_empty():diagnostics.append(selected+": "+error);value=DEFAULT
	return resolve(value)
static func activate(id:String,persist:bool=true)->Dictionary:
	var value:Resource=discover().get(id)
	var error:=validate(value,true)
	if not error.is_empty():return {"ok":false,"reason":error}
	if persist:
		var settings:=ConfigFile.new();var loaded:=settings.load(preference_path)
		if loaded!=OK and loaded!=ERR_FILE_NOT_FOUND:return {"ok":false,"reason":"Cannot read UI preferences"}
		settings.set_value("world_screens","active",id)
		if settings.save(preference_path)!=OK:return {"ok":false,"reason":"Cannot save UI preference"}
	session_id=id;return {"ok":true,"reason":"","id":id}
static func create(role:String)->Node:
	if not ROLES.has(role):return null
	var selected:=active();var script:Script=selected.get(role)
	var node:Node=script.new();node.set_meta("ui_set",selected);return node
