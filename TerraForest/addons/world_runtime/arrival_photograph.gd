# SPDX-License-Identifier: 0BSD
extends Node
## One clean playable frame for worlds without photographs. PNG encoding runs
## off-thread; only optional presentation sidecars are written after a real save.
## The earliest moment that makes sense is the first frame after the loading
## layer is hidden: earlier readbacks would store still-streaming terrain under a
## hidden loading cover. Exactly one frame is stored per world.
const Pictures=preload("res://addons/world_runtime/world_presentation.gd")
const RETRY_SECONDS:=0.5
const RETRY_LIMIT:=120
var game:Node
var directory:="user://worlds"
var image:Image
var worker:Thread
var pending_path:=""
var slot:=""
var captured:=false
var capturing:=false
var published:=false
var readbacks:=0
var attempts:=0
var presentation_ready:Callable
var ready_msec:=0
var captured_msec:=0
var wait_started:=0
func attach(host:Node,ready:Callable=Callable())->void:
	game=host;presentation_ready=ready;set_process(false);game.terrain.save_completed.connect(_saved)
func eligible()->bool:
	return is_instance_valid(game) and not game.temporary_world and not game.terrain.backend.readonly_snapshot and not game.shutdown_requested and DisplayServer.get_name()!="headless" and game.get_viewport() is Window
func request()->void:
	if captured or capturing:return
	if not eligible() or game.loading_active:
		_retry()
		return
	if ready_msec==0:ready_msec=Time.get_ticks_msec()
	slot=game.terrain.save_slot
	if not slot.is_valid_identifier() or slot.length()>48:return
	var image_check_started:=Time.get_ticks_usec()
	var existing:bool=Pictures.read_image(slot,directory,Vector2i(1,1))!=null
	if game.terrain.has_method("_record_stage"):game.terrain._record_stage("arrival existing image decode",(Time.get_ticks_usec()-image_check_started)/1000.0)
	if existing:captured=true;return
	capturing=true
	# Let the session's resource-loading cover be removed before reading the frame.
	await get_tree().process_frame
	var session:=get_tree().root.get_node_or_null("WorldSession")
	while eligible() and ((session!=null and is_instance_valid(session.cover)) or Pictures.popup_visible(game) or (presentation_ready.is_valid() and not presentation_ready.call())):
		if wait_started==0:
			wait_started=Time.get_ticks_msec()
			print("ARRIVAL_WAIT cover=",session!=null and is_instance_valid(session.cover)," popup=",Pictures.popup_visible(game)," entry=",presentation_ready.is_valid() and not presentation_ready.call()," windows=",_visible_windows())
		await get_tree().process_frame
	if wait_started>0:print("ARRIVAL_WAIT end ms=",Time.get_ticks_msec()-wait_started)
	if not eligible() or game.loading_active or (session!=null and is_instance_valid(session.cover)):
		capturing=false;_retry();return
	readbacks+=1
	image=await Pictures.capture_image(game,game.get_viewport())
	captured_msec=Time.get_ticks_msec()
	capturing=false;captured=image!=null
	if captured:_encode_if_saved()
	else:_retry()
## Skips and empty readbacks are retried instead of dropping the photograph.
func _retry()->void:
	if captured or attempts>=RETRY_LIMIT:return
	attempts+=1
	await get_tree().create_timer(RETRY_SECONDS).timeout
	if eligible():request.call_deferred()

func _visible_windows()->PackedStringArray:
	var names:=PackedStringArray()
	for window:Window in game.find_children("*","Window",true,false):
		if window.visible:names.append(String(window.name))
	return names
func _saved(success:bool)->void:
	if not success:return
	if image!=null:_encode_if_saved()
	elif not captured:request.call_deferred()
func _encode_if_saved()->void:
	if worker!=null or image==null or not FileAccess.file_exists(directory.path_join(slot+".trw")):return
	var folder:=directory.path_join(slot+".preview")
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return
	pending_path=folder.path_join("arrival.pending.png")
	worker=Thread.new()
	if worker.start(image.save_png.bind(pending_path))!=OK:worker=null;return
	# Keep the Image alive until the worker's native encoder has returned.
	set_process(true)
func _process(_delta:float)->void:
	if worker==null or worker.is_alive():return
	_publish(worker.wait_to_finish());worker=null;image=null;set_process(false)
func _publish(result:Error)->void:
	if result!=OK:
		if FileAccess.file_exists(pending_path):DirAccess.remove_absolute(pending_path)
		return
	var target:=directory.path_join(slot+".preview/arrival.png")
	if FileAccess.file_exists(target):DirAccess.remove_absolute(target)
	if DirAccess.rename_absolute(pending_path,target)==OK:
		published=true;Pictures.record_photographs(slot,directory)
		print("ARRIVAL_PHOTO slot=",slot," capture_ms=",captured_msec-ready_msec," published_ms=",Time.get_ticks_msec()-ready_msec," attempts=",attempts," readbacks=",readbacks)
	elif FileAccess.file_exists(pending_path):DirAccess.remove_absolute(pending_path)
func _exit_tree()->void:
	if worker!=null:_publish(worker.wait_to_finish());worker=null
