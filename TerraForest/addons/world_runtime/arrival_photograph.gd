# SPDX-License-Identifier: 0BSD
extends Node
## One clean playable frame for worlds without photographs. PNG encoding runs
## off-thread; only optional presentation sidecars are written after a real save.
const Pictures=preload("res://addons/world_runtime/world_presentation.gd")
var game:Node
var directory:="user://worlds"
var image:Image
var worker:Thread
var pending_path:=""
var slot:=""
var captured:=false
var capturing:=false
var published:=false
var presentation_ready:Callable
func attach(host:Node,ready:Callable=Callable())->void:
	game=host;presentation_ready=ready;set_process(false);game.terrain.save_completed.connect(_saved)
func eligible()->bool:
	return is_instance_valid(game) and not game.temporary_world and not game.terrain.backend.readonly_snapshot and not game.shutdown_requested and DisplayServer.get_name()!="headless" and game.get_viewport() is Window
func request()->void:
	if captured or capturing or not eligible() or game.loading_active:return
	slot=game.terrain.save_slot
	if not slot.is_valid_identifier() or slot.length()>48:return
	if Pictures.read_image(slot,directory,Vector2i(1,1))!=null:captured=true;return
	capturing=true
	# Let the session's resource-loading cover be removed before reading the frame.
	await get_tree().process_frame
	var session:=get_tree().root.get_node_or_null("WorldSession")
	while eligible() and ((session!=null and is_instance_valid(session.cover)) or Pictures.popup_visible(game) or (presentation_ready.is_valid() and not presentation_ready.call())):await get_tree().process_frame
	if not eligible() or game.loading_active or (session!=null and is_instance_valid(session.cover)):
		capturing=false;return
	image=await Pictures.capture_image(game,game.get_viewport())
	capturing=false;captured=image!=null
	if captured:_encode_if_saved()
	elif eligible():request.call_deferred()
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
	if result==OK and DirAccess.rename_absolute(pending_path,directory.path_join(slot+".preview/arrival.png"))==OK:
		published=true;Pictures.record_photographs(slot,directory)
	elif FileAccess.file_exists(pending_path):DirAccess.remove_absolute(pending_path)
func _exit_tree()->void:
	if worker!=null:_publish(worker.wait_to_finish());worker=null
