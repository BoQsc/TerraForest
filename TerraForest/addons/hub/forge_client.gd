# SPDX-License-Identifier: 0BSD
extends RefCounted
## Minimal Forge REST client for the hub (account summary, storage, files).
##
## `HTTPRequest` owns the TLS handshake and polling, so a concurrent realtime
## WebSocket cannot starve it on a busy headless frame loop. Shipped builds only
## read public files; upload and delete exist for publishing tools and need the
## secret key.
const Config=preload("res://addons/hub/config.gd")
const TIMEOUT:=20.0
const HTTP_GET:=0
const HTTP_POST:=1
const HTTP_DELETE:=3
var _request:=HTTPRequest.new()
var _queue:Array=[]
var _done:Array=[]
var _busy:=false
var _waited:=0.0
var _current:Dictionary={}
var _owner_node:Node
var _placed:=false
func _init()->void:
	_request.timeout=TIMEOUT
	_request.request_completed.connect(_completed)
func pending()->int:
	return _queue.size()+(1 if _busy else 0)
## Reads a public project file, e.g. get_public("news.json").
func get_public(path:String, key:="")->void:
	queue("/~/%s/%s" % [Config.PROJECT_ID,path],HTTP_GET,PackedByteArray(),key)
func get_api(path:String, key:="")->void:
	queue("/api/"+path.trim_prefix("/"),HTTP_GET,PackedByteArray(),key)
func upload(path:String, data:PackedByteArray, key:String)->void:
	queue("/api/files?path="+path.uri_encode(),HTTP_POST,data,key,"application/octet-stream")
func remove_file(path:String, key:String)->void:
	queue("/api/files?path="+path.uri_encode(),HTTP_DELETE,PackedByteArray(),key)
func queue(path:String, verb:=HTTP_GET, payload:=PackedByteArray(), key:="", content_type:="application/json")->void:
	_queue.append({"path":path,"verb":verb,"payload":payload,"key":key,"content_type":content_type})
## Starts the next queued call (once) and drives its timeout; the HTTPRequest
## node itself processes frames once it is inside the tree.
func poll(delta:float=0.0)->void:
	# The first poll only parks the HTTPRequest in the tree; a request can be
	# queued in the same frame, so the node must be live before it starts.
	if not _placed:
		_place()
		_placed=_request.get_parent()!=null and _request.is_inside_tree()
		if not _placed:
			# Without a tree (a bare RefCounted in a headless check) the
			# HTTPRequest cannot run; report a network failure instead of an
			# engine error. The next poll retries the placement (the caller may
			# simply poll before its node entered the tree).
			while not _queue.is_empty():
				_current={"path":str(_queue.pop_front().get("path",""))}
				_finish(0,"","Could not reach Forge")
			return
	if _busy:
		_waited+=delta if delta>0.0 else 1.0/60.0
		if _waited>TIMEOUT+2.0:_finish(0,"","Timed out contacting Forge")
		return
	if _queue.is_empty():return
	_current=_queue.pop_front()
	_busy=true
	_waited=0.0
	var headers:=PackedStringArray(["Accept: application/json","Connection: close","User-Agent: "+Config.USER_AGENT])
	if not str(_current.key).is_empty():headers.append("Authorization: Bearer "+str(_current.key))
	var method:=int(_current.verb)
	var body:=""
	if method!=HTTP_GET:
		headers.append("Content-Type: "+str(_current.content_type))
		body=str(_current.payload.get_string_from_utf8())
	var started:=_request.request(Config.BASE+str(_current.path),headers,_method_code(method),body)
	if started!=OK:_finish(0,"","Could not reach Forge")
## Inject the node that owns the HTTPRequest (defaults to the scene tree root).
func attach_to(host:Node)->void:
	_owner_node=host
func _place()->void:
	if _request.get_parent()!=null:return
	if _owner_node!=null and _owner_node.is_inside_tree():
		_owner_node.add_child(_request)
		return
	var loop:=Engine.get_main_loop()
	if loop is SceneTree:
		var host:Node=(loop as SceneTree).root
		if host!=null:host.add_child(_request)
func _method_code(verb:int)->HTTPClient.Method:
	match verb:
		HTTP_POST:return HTTPClient.METHOD_POST
		HTTP_DELETE:return HTTPClient.METHOD_DELETE
		_:return HTTPClient.METHOD_GET
func _completed(_result:int, code:int, _headers:PackedStringArray, body:PackedByteArray)->void:
	var text:=body.get_string_from_utf8()
	var parsed:Variant=null
	if not text.is_empty() and JSON.new().parse(text)==OK:parsed=JSON.parse_string(text)
	var ok:bool=code>=200 and code<300 and not (parsed is Dictionary and parsed.get("ok",true)==false)
	var error:=""
	if not ok:
		if parsed is Dictionary and parsed.has("error"):error=str(parsed.error)
		elif code==0:error="Could not reach Forge"
		else:error="HTTP %d: %s" % [code,text.strip_edges().left(160)]
	_done.append({"path":str(_current.get("path","")),"ok":ok,"code":code,"data":parsed,"error":error,"bytes":body})
	_current={}
	_busy=false
	_waited=0.0
func _finish(code:int, data:Variant, error:String)->void:
	_done.append({"path":str(_current.get("path","")),"ok":error.is_empty() and code>=200 and code<300,"code":code,"data":data,"error":error,"bytes":PackedByteArray()})
	_current={}
	_busy=false
	_waited=0.0
func take_results()->Array:
	var out:=_done.duplicate()
	_done.clear()
	return out
static func error_text(value:Variant)->String:
	return str(value.get("error","")) if value is Dictionary else ""
