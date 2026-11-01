# SPDX-License-Identifier: 0BSD
extends Node
## Read-only browser work. Workers return values/images; UI and textures stay here.
signal catalog_ready(slots:PackedStringArray)
signal details_ready(slot:String,details:Dictionary,picture:Texture2D)
const Launch=preload("res://demo/world_launch.gd")
const Presentation=preload("res://addons/world_runtime/world_presentation.gd")
const CACHE_LIMIT:=8
const THUMBNAIL_SIZE:=Vector2i(760,400)
var directory:="user://worlds"
var loading:=false
var worker:Thread
var revision:=0
var job_revision:=0
var job_slot:=""
var scanning:=false
var scan_pending:=false
var include_preparation:=false
var order:="played"
var selected_slot:=""
var cache:Dictionary={}

func refresh(include_drafts:bool=false,sort_by:String="played")->void:
	revision+=1;cache.clear()
	include_preparation=include_drafts;order=sort_by
	loading=true;scan_pending=true
	_start_next()

func select(slot:String)->void:
	selected_slot=slot
	if cache.has(slot):
		var entry:Dictionary=cache[slot]
		cache.erase(slot);cache[slot]=entry # Keep recently visited worlds.
		details_ready.emit(slot,entry.details,entry.picture)
	_start_next()

func _start_next()->void:
	if worker!=null:return
	var job:Callable
	if scan_pending:
		scan_pending=false;scanning=true
		job=Launch.saved_slots.bind(directory,include_preparation,order)
	elif not selected_slot.is_empty() and not cache.has(selected_slot):
		scanning=false;job_slot=selected_slot
		job=_read_details.bind(job_slot,directory)
	else:return
	job_revision=revision
	worker=Thread.new()
	if worker.start(job)==OK:return
	# A failed worker must leave usable controls and must not retry every frame.
	worker=null
	if scanning:
		loading=false;catalog_ready.emit(PackedStringArray())
	else:
		cache[job_slot]={"details":{},"picture":null}
		details_ready.emit(job_slot,{},null)

func _process(_delta:float)->void:
	if worker==null or worker.is_alive():return
	var result:Variant=worker.wait_to_finish();worker=null
	if job_revision==revision:
		if scanning:
			loading=false;catalog_ready.emit(result)
		else:
			var picture:Texture2D=null
			if result.image!=null:picture=ImageTexture.create_from_image(result.image)
			if cache.size()>=CACHE_LIMIT:cache.erase(cache.keys()[0])
			cache[job_slot]={"details":result.details,"picture":picture}
			if selected_slot==job_slot:details_ready.emit(job_slot,result.details,picture)
	_start_next()

static func _read_details(slot:String,folder:String)->Dictionary:
	var image:Image=null
	# Stable photograph while browsing; full-resolution loading backgrounds keep
	# their existing selection policy. Source PNGs and saved worlds are untouched.
	if slot.is_valid_identifier() and slot.length()<=48:
		for view:String in ["north","road","market"]:
			var path:=folder.path_join(slot+".preview").path_join(view+".png")
			if not FileAccess.file_exists(path):continue
			image=Image.load_from_file(path)
			if image==null or image.is_empty():
				image=null;continue
			var scale:=minf(1.0,minf(float(THUMBNAIL_SIZE.x)/image.get_width(),float(THUMBNAIL_SIZE.y)/image.get_height()))
			if scale<1.0:image.resize(maxi(1,roundi(image.get_width()*scale)),maxi(1,roundi(image.get_height()*scale)),Image.INTERPOLATE_BILINEAR)
			break
	return {"details":Presentation.details(slot,folder),"image":image}

func _exit_tree()->void:
	if worker!=null:worker.wait_to_finish();worker=null
