# SPDX-License-Identifier: 0BSD
extends RefCounted
## Hub chat model: rooms, presence and message history over Forge realtime.
##
## Messages travel as {"type":"event","event":"tf.chat","data":{...}} so they are
## namespaced away from future gameplay events. History keeps at most
## MAX_LINES per room, newest last, and survives room switches in memory.
const Config=preload("res://addons/hub/config.gd")
const Realtime=preload("res://addons/hub/realtime.gd")
const Identity=preload("res://addons/hub/identity.gd")
const EVENT_CHAT:="tf.chat"
const MAX_LINES:=200
const MAX_TEXT:=400
const OFFLINE:="offline"
	
const CONNECTING:="connecting"
const LINK_CLOSED:=0
signal room_changed(room_name:String)
signal message_added(room_name:String, line:Dictionary)
signal presence_changed(room_name:String, peers:Array)
signal link_changed(state:int, detail:String)
var identity:Dictionary={}
var rooms:=PackedStringArray([Config.ROOM_GENERAL])
var history:Dictionary={}
var presence:Dictionary={}
var current_room:=Config.ROOM_GENERAL
var link_state:=LINK_CLOSED
var link_detail:=""
var _net
var _start_after:=0.0
func _init(local_identity:Dictionary={})->void:
	identity=local_identity if not local_identity.is_empty() else Identity.load_or_create()
func display_name()->String:
	return Identity.display(identity)
func status()->int:
	return LINK_CLOSED if _net==null else int(_net.status)
func state_name()->String:
	if _net==null:return OFFLINE
	var name_value:String=_net.state_name()
	return name_value
## Saves the nickname and re-announces it to the room (no reconnect needed).
func set_nickname(value:String)->void:
	var clean:=Identity.clean_nickname(value)
	if clean.is_empty() or clean==str(identity.get("nickname","")):return
	identity["nickname"]=clean
	Identity.save(identity)
	if _net!=null:
		_net.nickname=display_name()
		_net.announce()
## Opens the room socket. `connect_in` (seconds) lets callers stagger several
## sockets so the first one's handshake is not still ticking when others start.
func start(connect_in:=0.0)->void:
	if _net!=null:return
	_net=Realtime.new(current_room,display_name())
	_net.on_status=func(value:int):
		link_state=value
		link_detail="" if value==1 else str(_net.last_error)
		link_changed.emit(link_state,link_detail)
	_net.on_message=_on_message
	if connect_in>0.0:
		_start_after=connect_in
		return
	if not _net.connect_now():link_detail=str(_net.last_error)
func stop()->void:
	if _net==null:return
	_net.close()
	_net=null
	link_state=LINK_CLOSED
func tick(delta:float)->void:
	if _net==null:return
	if _start_after>0.0:
		_start_after=maxf(0.0,_start_after-delta)
		if _start_after>0.0:return
		_start_after=0.0
		if not _net.connect_now():link_detail=str(_net.last_error)
		return
	_net.poll(delta)
	link_state=int(_net.status)
	link_detail="" if link_state==1 else str(_net.last_error)
func switch_room(room_name:String)->void:
	if room_name.is_empty() or room_name==current_room:return
	current_room=room_name
	presence.erase(room_name)
	room_changed.emit(room_name)
	if _net!=null:_net.join(room_name)
func add_room(room_name:String)->void:
	if room_name.is_empty() or rooms.has(room_name):return
	rooms.append(room_name)
## Joins (and remembers) the room dedicated to a saved world slot.
func open_world_room(slot:String)->void:
	add_room(Config.room_for_world(slot))
	switch_room(Config.room_for_world(slot))
func lines(room_name:=current_room)->Array:
	return history.get(room_name,[])
func peers(room_name:=current_room)->Array:
	return presence.get(room_name,[])
func send_text(text:String)->bool:
	var clean:=_sanitize(text)
	if clean.is_empty():return false
	if _net==null or int(_net.status)!=2:
		_append(current_room,{"kind":"error","nickname":"system","text":"Chat is offline; your message was not sent.","ts":_now_ms()})
		return false
	var sent:bool=_net.send({"type":"event","event":EVENT_CHAT,"data":{"text":clean,"nickname":display_name(),"room":current_room,"v":1}})
	if sent:
		_append(current_room,{"kind":"chat","nickname":display_name(),"peer_id":_net.peer_id,"text":clean,"ts":_now_ms(),"self":true})
	else:
		_append(current_room,{"kind":"error","nickname":"system","text":"Forge refused the message.","ts":_now_ms()})
	return sent
## Adds a history line (used by the model itself and by headless checks).
func be_line(room_name:String, line:Dictionary)->void:
	_append(room_name,line)
## Routes one Forge realtime frame (same path as the live socket).
func be_message(message:Dictionary)->void:
	_on_message(message)
func _on_message(message:Dictionary)->void:
	match str(message.get("type","")):
		"event":
			if str(message.get("event",""))!=EVENT_CHAT or not message.get("data") is Dictionary:return
			var data:Dictionary=message.data
			var peer:=str(message.get("peer_id",data.get("peer_id","")))
			if _net!=null and not str(_net.peer_id).is_empty() and peer==str(_net.peer_id):return
			var room_name:=str(data.get("room",current_room))
			var text:=_sanitize(str(data.get("text","")))
			if text.is_empty():return
			_append(room_name,{"kind":"chat","nickname":str(message.get("nickname",data.get("nickname","anonymous"))),"peer_id":peer,"text":text,"ts":int(message.get("ts",_now_ms()))})
		"message":
			if not message.get("data") is Dictionary:return
			var dm:Dictionary=message.data
			var text:=_sanitize(str(dm.get("text",dm.get("message",""))))
			if text.is_empty():return
			_append("dm",{"kind":"dm","nickname":str(message.get("nickname",dm.get("nickname","anonymous"))),"text":text,"ts":int(message.get("ts",_now_ms()))})
		"presence":
			var room_name:=str(message.get("room",current_room))
			presence[room_name]=message.get("peers",[])
			presence_changed.emit(room_name,presence[room_name])
		"joined":
			var room_name:=str(message.get("room",""))
			if not room_name.is_empty() and room_name!=current_room:
				current_room=room_name
				room_changed.emit(room_name)
		"ready":
			# A fresh socket joins the URL room; make sure our room and
			# nickname are applied once it is open.
			if _net!=null:
				_net.room=current_room
				_net.announce()
func _append(room_name:String, line:Dictionary)->void:
	var key:=room_name if not room_name.is_empty() else current_room
	var list:Array=history.get(key,[])
	list.append(line)
	while list.size()>MAX_LINES:list.pop_front()
	history[key]=list
	message_added.emit(key,line)
static func _sanitize(text:String)->String:
	var out:=""
	for i:int in text.length():
		if out.length()>=MAX_TEXT:break
		var code:=text.unicode_at(i)
		if code==9 or code==10:out+=" "
		elif code>=32 and code!=127:out+=text[i]
	return out.strip_edges()
## Strips BBCode-ish brackets so an untrusted peer cannot restyle the UI.
static func plain(text:String)->String:
	return text.replace("[","(").replace("]",")")
## Bare message texts in `room_name`, for summaries and headless checks.
func texts(room_name:=current_room)->Array:
	var out:Array=[]
	for line:Dictionary in lines(room_name):
		if str(line.get("kind",""))=="chat":out.append(str(line.get("text","")))
	return out
static func _now_ms()->int:
	return int(Time.get_unix_time_from_system()*1000.0)
