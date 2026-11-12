# SPDX-License-Identifier: 0BSD
extends RefCounted
## News / issues feeds read from public Forge project files.
##
## Offline first: every successful read is cached in user://hub/<name>.json and
## served when Forge is unreachable. Invalid data never replaces a good cache.
const ForgeClient=preload("res://addons/hub/forge_client.gd")
const CACHE_DIR:="user://hub"
const FILES:={"news":"news.json","issues":"issues.json"}
## feed -> {"items":Array,"cached":bool,"error":String}
var data:Dictionary={}
var on_update:Callable
var _client:ForgeClient
var _inflight:=""
var _pending:Array=[]
## Hosts the HTTPRequest under an existing node instead of the tree root.
func attach_to(host:Node)->void:
	if _client==null:_client=ForgeClient.new()
	_client.attach_to(host)
func refresh(feed:String)->void:
	if not FILES.has(feed):return
	if _client==null:_client=ForgeClient.new()
	if _inflight.is_empty():
		_inflight=feed
		_client.get_public(FILES[feed])
	elif not _pending.has(feed):
		_pending.append(feed)
func poll(delta:float=0.0)->void:
	if _client==null:return
	_client.poll(delta)
	for result:Dictionary in _client.take_results():
		var feed:=_inflight
		_inflight=""
		if not feed.is_empty():
			apply(feed,result)
			if on_update.is_valid():on_update.call(feed)
		if not _pending.is_empty():refresh(_pending.pop_front())
## Merges one Forge result into `data` (also used by headless checks).
func apply(feed:String, result:Dictionary)->void:
	var items:Array=[]
	var value:Variant=result.get("data",null)
	var parsed:=false
	if value is Array:
		items=value
		parsed=true
	elif value is Dictionary and value.get("items",null) is Array:
		items=value.items
		parsed=true
	if parsed:
		write_cache(feed,items)
		data[feed]={"items":items,"cached":false,"error":""}
		return
	var error:=str(result.get("error",""))
	if error.is_empty():error="feed format not recognised"
	var cached:=read_cache(feed) if feed!="issues" else []
	# Forge answers 301 for files that are not published yet; a stale cache is
	# still better than an empty tab, so report exactly where the items came from.
	if not cached.is_empty():
		data[feed]={"items":cached,"cached":true,"error":"Showing saved copy (%s)" % error}
	else:
		data[feed]={"items":[],"cached":false,"error":"Nothing published yet (%s)" % error}
static func cache_path(feed:String)->String:
	return CACHE_DIR+"/"+feed+".json"
static func write_cache(feed:String, items:Array)->void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var file:=FileAccess.open(cache_path(feed),FileAccess.WRITE)
	if file==null:return
	file.store_string(JSON.stringify({"items":items,"saved":int(Time.get_unix_time_from_system())}))
	file.close()
static func read_cache(feed:String)->Array:
	if not FileAccess.file_exists(cache_path(feed)):return []
	var text:=FileAccess.get_file_as_string(cache_path(feed))
	if JSON.new().parse(text)!=OK:return []
	var parsed:Variant=JSON.parse_string(text)
	if parsed is Dictionary and parsed.get("items",null) is Array:return parsed.items
	return []
func items(feed:String)->Array:
	return data.get(feed,{}).get("items",[])
func is_cached(feed:String)->bool:
	return bool(data.get(feed,{}).get("cached",false))
func error(feed:String)->String:
	return str(data.get(feed,{}).get("error",""))
## Latest version announced in news.json ("latest_version"). Display only: the
## update placeholder never downloads or installs anything.
func latest_version()->String:
	for entry:Variant in items("news"):
		if entry is Dictionary and entry.has("latest_version"):
			return str(entry.get("latest_version",""))
	return ""
