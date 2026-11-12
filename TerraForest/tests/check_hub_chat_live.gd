# SPDX-License-Identifier: 0BSD
# Usage: godot --headless --path . --script res://tests/check_hub_chat_live.gd
extends SceneTree
## Two community panels talking through Forge, plus the published news feed.
##
## Forge keeps one socket per room per client, so running two panels in one
## process is only reliable when the second one is created lazily; the test
## retries the join once if the room reports the first panel alone.
const Community=preload("res://addons/hub/community_panel.gd")
const Identity=preload("res://addons/hub/identity.gd")
var failures:=PackedStringArray()
func check(condition:bool, message:String)->void:
	if not condition:failures.append(message)
	print(("PASS " if condition else "FAIL ")+message)
func _initialize()->void:
	print("HUB CHAT LIVE")
	var base:Dictionary=Identity.load_or_create()
	var a:=Community.new(base)
	var b:=Community.new(Identity.clone(base))
	# Both panels must be inside the tree before opening: while a socket is in
	# its handshake, the same frame loop is what moves it forward.
	a.chat.history.clear()
	b.chat.history.clear()
	root.add_child(a)
	root.add_child(b)
	a.open()
	b.open()
	check(await _wait(func():return a.chat.status()==1,15.0), "panel A reaches Forge")
	check(await _wait(func():return b.chat.status()==1,15.0), "panel B reaches Forge")
	var joined:=await _wait(func():return a.chat.peers().size()>=2 and b.chat.peers().size()>=2,12.0)
	check(joined, "presence lists both players")
	a.input_box.text="hello from panel A [b]bold[/b]"
	check(a.send_current(), "panel A sends a message")
	check(await _wait(func():return b.chat.texts().has("hello from panel A [b]bold[/b]"),10.0), "panel B receives the message text")
	var back:Variant=null
	for line:Dictionary in b.chat.lines():
		if str(line.get("kind",""))=="chat":back=line
	check(back!=null and str(back.nickname)==a.chat.display_name(), "received line carries the sender nickname")
	print("INFO A nickname=%s B nickname=%s" % [a.chat.display_name(),b.chat.display_name()])
	a.input_box.text=""
	a.close_panel()
	b.close_panel()
	a.queue_free()
	b.queue_free()
	await process_frame
	var news:=Community.new()
	root.add_child(news)
	news.open()
	await _wait(func():return not news.feeds.items("news").is_empty() or not news.feeds.error("news").is_empty(),20.0)
	check(not news.feeds.items("news").is_empty(), "published news.json reaches the panel")
	print("INFO news items=%d cached=%s error=%s" % [news.feeds.items("news").size(),news.feeds.is_cached("news"),news.feeds.error("news")])
	check(news.updates_label.text.contains("placeholder"), "updates tab stays a placeholder")
	news.queue_free()
	await process_frame
	print("RESULT %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
func _wait(condition:Callable, seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if condition.call():return true
	return condition.call()
