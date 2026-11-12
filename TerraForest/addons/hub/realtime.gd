# SPDX-License-Identifier: 0BSD
extends RefCounted
## Forge realtime room connection (JSON frames via `?fmt=j`).
##
## Verified against the live service: connecting yields {"type":"ready",
## "peer_id",...} then {"type":"presence","peers":[...],"ts","seq"}; sending
## {"type":"join"} moves the socket to the room named "join". Every message is
## forwarded to `on_message` untouched so the chat layer owns the schema.
const Config=preload("res://addons/hub/config.gd")
enum State{CLOSED,CONNECTING,OPEN}
const MAX_RETRY_MS:=30000
var room:=""
var nickname:="anonymous"
var status:=State.CLOSED
var peer_id:=""
var last_error:=""
var on_status:Callable
var on_message:Callable
var _socket:=WebSocketPeer.new()
var _retry_at:=0
var _attempt:=0
var _frames:=0
func _init(room_name:String, display_name:="anonymous")->void:
	room=room_name
	nickname=display_name
func url()->String:
	return "wss://%s/api/socket?project=%s&room=%s&fmt=j&nick=%s" % [Config.host(),Config.PROJECT_ID,room.uri_encode(),nickname.uri_encode()]
func connect_now()->bool:
	_socket=WebSocketPeer.new()
	_socket.inbound_buffer_size=262144
	_socket.outbound_buffer_size=65536
	last_error=""
	_retry_at=0
	change_state(State.CONNECTING)
	var err:=_socket.connect_to_url(url())
	if err!=OK:
		last_error="Could not start the room connection (%d)" % err
		_schedule_retry()
		return false
	return true
func close()->void:
	if _socket.get_ready_state()==WebSocketPeer.STATE_OPEN:_socket.close(1000,"bye")
	_retry_at=0
	change_state(State.CLOSED)
## Moves this socket into another room on the same project (room limit 60).
func join(new_room:String)->void:
	if new_room.is_empty():return
	room=new_room
	send({"type":"join","room":room,"nickname":nickname})
## Re-announces the current nickname (Forge applies it with the join frame).
func announce()->void:
	send({"type":"join","room":room,"nickname":nickname})
func send(payload:Dictionary)->bool:
	if status!=State.OPEN:
		last_error="The room is not open yet"
		return false
	if _socket.send_text(JSON.stringify(payload))!=OK:
		last_error="Room refused the message"
		return false
	return true
func poll(delta:float)->void:
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if status!=State.OPEN:
				change_state(State.OPEN)
				_attempt=0
		WebSocketPeer.STATE_CLOSED:
			if status!=State.CLOSED:
				if last_error.is_empty():last_error="Room connection closed"
				_schedule_retry()
			elif _retry_at>0 and Time.get_ticks_msec()>=_retry_at:
				connect_now()
			return
		_:
			return
	while _socket.get_available_packet_count()>0:
		_handle(_socket.get_packet().get_string_from_utf8())
func _handle(text:String)->void:
	var message:Variant=JSON.parse_string(text)
	if not message is Dictionary:return
	match str(message.get("type","")):
		"ready":
			peer_id=str(message.get("peer_id",peer_id))
			room=str(message.get("room",room))
			nickname=str(message.get("nickname",nickname))
		"error":last_error=str(message.get("error","Room error"))
		"joined":
			room=str(message.get("room",room))
			last_error=""
	if on_message.is_valid():on_message.call(message)
func _schedule_retry()->void:
	_attempt=mini(_attempt+1,6)
	_retry_at=Time.get_ticks_msec()+mini(MAX_RETRY_MS,1000*(1 << (_attempt-1)))
	change_state(State.CLOSED)
func change_state(value:int)->void:
	status=value
	if on_status.is_valid():on_status.call(status)
func state_name()->String:
	match status:
		State.OPEN:return "online"
		State.CONNECTING:return "connecting"
		_:return "offline"
func retry_in_ms()->int:
	return maxi(0,_retry_at-Time.get_ticks_msec())
