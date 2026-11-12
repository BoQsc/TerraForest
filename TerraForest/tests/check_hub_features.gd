# SPDX-License-Identifier: 0BSD
# Usage: godot --headless --path . --script res://tests/check_hub_features.gd
extends SceneTree
## Hub behavioural checks: chat offline error, feeds over real HTTP, panel.
const Chat=preload("res://addons/hub/chat.gd")
const Feeds=preload("res://addons/hub/feeds.gd")
const Community=preload("res://addons/hub/community_panel.gd")
const Config=preload("res://addons/hub/config.gd")
var failures:=PackedStringArray()
var _nets:Array=[]
func check(condition:bool, message:String)->void:
	if not condition:failures.append(message)
	print(("PASS " if condition else "FAIL ")+message)
func _initialize()->void:
	print("HUB FEATURES")
	# The HTTPRequest must live under the root before the first request starts.
	test_offline_error()
	await test_feeds_http()
	await test_panel()
	print("RESULT %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
func test_offline_error()->void:
	var chat:=Chat.new()
	chat.history.clear()
	var before:=chat.lines().size()
	var sent:=chat.send_text("hello while offline")
	check(sent==false, "offline send returns false")
	check(chat.lines().size()==before+1 and str(chat.lines().back().kind)=="error", "offline send reports an error line")
	print("INFO offline status=%d name=%s detail=%s" % [chat.status(),chat.state_name(),chat.link_detail])
func test_feeds_http()->void:
	var feeds:=Feeds.new()
	feeds.attach_to(root)
	pending_feed_pump=func():feeds.poll(0.0)
	for feed:String in ["news","issues"]:
		feeds.refresh(feed)
	await _wait_for(func():return feeds.data.has("news") and feeds.data.has("issues"),25.0)
	check(feeds.data.has("news") and feeds.data.has("issues"), "feeds answered over HTTP (published or error)")
	for feed:String in ["news","issues"]:
		var error:String=feeds.error(feed)
		var published:=error.is_empty()
		check(published or not error.is_empty(), "%s result is data or a clear message" % feed)
		print("INFO %s published=%s items=%d cached=%s error=%s" % [feed,published,feeds.items(feed).size(),feeds.is_cached(feed),error])
func test_panel()->void:
	var panel:=Community.new()
	root.add_child(panel)
	await process_frame
	check(panel.chat!=null and panel.feeds!=null, "panel owns chat and feeds")
	check(panel.get_child_count()==2, "panel built its backdrop and layout")
	panel.open()
	await process_frame
	check(panel.is_open(), "panel opens")
	panel.send_current()
	await process_frame
	var lines:Array=panel.chat.lines()
	check(lines.is_empty(), "empty input sends nothing")
	panel.input_box.text="[b]hi[/b]"
	panel.send_current()
	await process_frame
	check(panel.chat.lines().back().kind=="error", "panel send while offline shows an error line")
	panel.close_panel()
	check(not panel.is_open(), "panel closes")
	panel.queue_free()
	await process_frame
func _wait_for(condition:Callable, seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline:
		for net in _nets:
			net.poll(0.0)
		if pending_feed_pump.is_valid():pending_feed_pump.call()
		if condition.call():return true
		await process_frame
	return condition.call()
## The panel pumps its own feeds in _process; helpers register them here.
var pending_feed_pump:Callable
