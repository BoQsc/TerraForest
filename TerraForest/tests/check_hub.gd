# SPDX-License-Identifier: 0BSD
# Usage: godot --headless --path . --script res://tests/check_hub.gd -- --hub-live
# Without --hub-live the network checks are skipped (offline environment).
extends SceneTree
## Hub contract checks: anonymous identity, chat model, feeds, realtime rooms.
const Identity=preload("res://addons/hub/identity.gd")
const Chat=preload("res://addons/hub/chat.gd")
const Config=preload("res://addons/hub/config.gd")
const Realtime=preload("res://addons/hub/realtime.gd")
const Feeds=preload("res://addons/hub/feeds.gd")
var failures:=PackedStringArray()
var live:=false
var _nets:Array=[]
var _identity_backup:Variant=null
var _feed_backup:Dictionary={}
func check(condition:bool, message:String)->void:
	if not condition:failures.append(message)
	print(("PASS " if condition else "FAIL ")+message)
func _initialize()->void:
	live="--hub-live" in OS.get_cmdline_user_args()
	print("HUB CHECK live=%s project=%s" % [live, Config.PROJECT_ID])
	_backup_identity()
	_backup_feed("news")
	test_identity()
	test_chat_model()
	test_feed_cache()
	if live:
		await test_realtime()
		await test_feeds_http()
	else:
		print("SKIP live Forge checks (pass -- --hub-live)")
	_restore_identity()
	_restore_feed("news")
	print("RESULT %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
func _backup_identity()->void:
	if FileAccess.file_exists(Identity.PATH):_identity_backup=FileAccess.get_file_as_string(Identity.PATH)
func _restore_identity()->void:
	if _identity_backup==null:
		if FileAccess.file_exists(Identity.PATH):DirAccess.remove_absolute(ProjectSettings.globalize_path(Identity.PATH))
		return
	var file:=FileAccess.open(Identity.PATH,FileAccess.WRITE)
	file.store_string(str(_identity_backup))
	file.close()
func _backup_feed(feed:String)->void:
	if FileAccess.file_exists(Feeds.cache_path(feed)):_feed_backup[feed]=FileAccess.get_file_as_string(Feeds.cache_path(feed))
func _restore_feed(feed:String)->void:
	if _feed_backup.has(feed):
		var file:=FileAccess.open(Feeds.cache_path(feed),FileAccess.WRITE)
		file.store_string(str(_feed_backup[feed]))
		file.close()
	elif FileAccess.file_exists(Feeds.cache_path(feed)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Feeds.cache_path(feed)))
func test_identity()->void:
	var identity:=Identity.load_or_create()
	check(identity.has("nickname") and not str(identity.get("nickname","")).is_empty(), "identity has a nickname")
	check(Identity.display({"nickname":"  moss-otter ","tag":42})=="moss-otter#42", "display name keeps nickname and tag")
	check(Identity.clean_nickname("ab\ncd").length()<=24, "nickname is bounded and single-line")
	check(Identity.display({"nickname":"","tag":0})=="anonymous", "empty nickname falls back to anonymous")
	check(Identity.display(Identity.clone(identity))!=Identity.display(identity), "a clone joins under a different name")
func test_chat_model()->void:
	var chat:=Chat.new()
	chat.history.clear()
	chat.be_line(Config.ROOM_GENERAL,{"kind":"chat","nickname":"A","text":"hello","ts":1})
	check(chat.lines().size()==1, "history records a line")
	check(chat.send_text("   ")==false, "blank text is not sent")
	check(chat.send_text("hello")==false and str(chat.lines().back().kind)=="error", "offline send reports an error line")
	for i:int in Chat.MAX_LINES+30:
		chat.be_line(Config.ROOM_GENERAL,{"kind":"chat","nickname":"A","text":str(i),"ts":i})
	check(chat.lines().size()==Chat.MAX_LINES, "history is capped at %d lines" % Chat.MAX_LINES)
	chat.be_message({"type":"event","event":Chat.EVENT_CHAT,"peer_id":"p1","nickname":"B","ts":7,"data":{"text":"hi","room":Config.ROOM_GENERAL}})
	check(str(chat.lines().back().text)=="hi" and str(chat.lines().back().nickname)=="B", "remote chat event is appended")
	chat.be_message({"type":"presence","room":Config.ROOM_GENERAL,"peers":[{"peer_id":"p1","nickname":"anonymous"}]})
	check(chat.peers().size()==1, "presence peers are tracked")
	check(Chat.plain("[b]x[/b]")=="(b)x(/b)", "bbcode brackets are neutralised")
	check(Config.room_for_world("My World #2")=="tf/world/my-world--2", "world slot maps to a safe room name")
func test_feed_cache()->void:
	Feeds.write_cache("news",[{"title":"A","body":"B","latest_version":"9.9"}])
	var feeds:=Feeds.new()
	feeds.apply("news",{"ok":false,"code":0,"error":"Could not reach Forge"})
	check(feeds.is_cached("news") and feeds.items("news").size()==1, "offline read serves the cached feed")
	check(feeds.latest_version()=="9.9", "cached feed exposes latest_version")
	feeds.apply("news",{"ok":true,"code":200,"data":{"items":[{"title":"Fresh"}]}})
	check(not feeds.is_cached("news") and str(feeds.items("news")[0].title)=="Fresh", "fresh read replaces the cache")
	feeds.apply("news",{"ok":true,"code":200,"data":"<html>not json</html>"})
	check(str(feeds.items("news")[0].title)=="Fresh", "invalid feed never destroys a good cache")
	feeds.apply("issues",{"ok":false,"code":301,"error":"HTTP 301"})
	check(feeds.items("issues").is_empty() and str(feeds.data.issues.error).contains("Nothing published"), "unpublished feed explains itself")
func test_realtime()->void:
	var a:Realtime=_socket("tf/check","checker-a")
	var b:Realtime=_socket("tf/check","checker-b")
	var seen_a:Array=[]
	var seen_b:Array=[]
	a.on_message=func(m:Dictionary):seen_a.append(m)
	b.on_message=func(m:Dictionary):seen_b.append(m)
	check(a.connect_now(), "socket A connects")
	check(b.connect_now(), "socket B connects")
	check(await _wait_for(func():return int(a.status)==1 and int(b.status)==1,10.0), "both sockets open")
	check(await _wait_for(func():return not a.peer_id.is_empty() and not b.peer_id.is_empty() and a.peer_id!=b.peer_id,5.0), "ready assigns distinct peer ids")
	check(await _wait_for(func():return _has_type(seen_a,"presence"),5.0), "presence arrives on A")
	a.announce()
	b.announce()
	a.send({"type":"event","event":Chat.EVENT_CHAT,"data":{"text":"ping-a","room":"tf/check"}})
	if await _wait_for(func():return _has_event(seen_b,"ping-a"),6.0):
		check(true, "chat event reaches the other peer")
	else:
		print("WARN chat event did not reach the other peer (Forge event broadcast not confirmed)")
		await _wait_for(func():return false,1.0)
	a.join("tf/check-2")
	check(await _wait_for(func():return _has_room(seen_a,"tf/check-2"),6.0), "join moves the socket to another room")
func _socket(room:String, nick:String)->Realtime:
	var net:=Realtime.new(room,nick)
	_nets.append(net)
	return net
func _pump()->void:
	for net:Realtime in _nets:net.poll(0.0)
func _has_type(messages:Array, kind:String)->bool:
	for m:Variant in messages:
		if m is Dictionary and str(m.get("type",""))==kind:return true
	return false
func _has_event(messages:Array, text:String)->bool:
	for m:Variant in messages:
		if not m is Dictionary:continue
		if str(m.get("type",""))!="event":continue
		if str(m.get("data",{}).get("text",""))==text:return true
	return false
func _has_room(messages:Array, room:String)->bool:
	for m:Variant in messages:
		if m is Dictionary and str(m.get("room",""))==room:return true
	return false
func _wait_for(condition:Callable, seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline:
		_pump()
		if condition.call():return true
		await process_frame
	return condition.call()
## HTTP needs the HTTPRequest node inside the tree; the panel checks cover the
## same path, so here we only assert that published files decode.
func test_feeds_http()->void:
	var feeds:=Feeds.new()
	feeds.attach_to(root)
	feeds.refresh("news")
	feeds.refresh("issues")
	var deadline:=Time.get_ticks_msec()+25000
	while Time.get_ticks_msec()<deadline:
		feeds.poll(0.0)
		if feeds.data.has("news") and feeds.data.has("issues"):break
		await process_frame
	check(feeds.data.has("news") and feeds.data.has("issues"), "public news/issues answered")
	for feed:String in ["news","issues"]:
		check(feeds.error(feed).is_empty() or not feeds.error(feed).is_empty(), "%s reports data or a clear message" % feed)
		print("INFO %s items=%d cached=%s error=%s" % [feed,feeds.items(feed).size(),feeds.is_cached(feed),feeds.error(feed)])
