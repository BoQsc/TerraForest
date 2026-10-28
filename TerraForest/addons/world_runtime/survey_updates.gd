# SPDX-License-Identifier: 0BSD
extends Node
# Bounded presentation queue; all density evaluation stays on the native worker.
var atlas:Node
var terrain:Node
var image:Image
var displayed:Image
var dirty:Dictionary={}
var pending:Dictionary={}
var in_flight_limit:=1
var serial:=0
var patches:=0
var max_native_ms:=0.0
var epoch:=-1
const Cache=preload("res://addons/world_runtime/survey_patch_cache.gd")
var identity_checked:=false
var cache_identity:=""
var cache_revision:=-1
var cache_saved:=false
var cache_hits:=0
var cache_writes:=0
var io:Thread
var io_job:Dictionary={}
const SIZE:=1024
const TILE:=16
var upload_pending:=false
var last_upload:=0

func _ready()->void:
 terrain=atlas.game.terrain
 terrain.region_changed.connect(changed)
 terrain.survey_patch_ready.connect(receive)
 set_process(false)
func reset()->void:
 epoch=terrain.epoch;image=null;displayed=null;dirty.clear();pending.clear();upload_pending=false
 identity_checked=false;cache_identity="";cache_revision=-1;cache_saved=false
 for cell:Vector2i in terrain.modified_columns:
  changed(AABB(Vector3(cell.x*16,0,cell.y*16),Vector3(16,256,16)),0)
func changed(bounds:AABB,_revision:int)->void:
 identity_checked=false;cache_identity="";cache_saved=false
 var low:=Vector2i(floori((bounds.position.x-8)*SIZE/2000/TILE),floori((bounds.position.z-8)*SIZE/2000/TILE)).clamp(Vector2i.ZERO,Vector2i(63,63))
 var high:=Vector2i(floori((bounds.end.x+8)*SIZE/2000/TILE),floori((bounds.end.z+8)*SIZE/2000/TILE)).clamp(Vector2i.ZERO,Vector2i(63,63))
 for z in range(low.y,high.y+1):
  for x in range(low.x,high.x+1):dirty[Vector2i(x,z)]=true
func _process(_delta:float)->void:
 if io!=null:
  if io.is_alive():return
  var result:Dictionary=io.wait_to_finish();io=null
  if io_job.kind=="write":
   if result.get("persisted",false):cache_writes+=1
  elif result.get("hit",false) and image!=null and io_job.epoch==epoch and terrain.epoch==epoch and io_job.revision==terrain.density_revision and not terrain.pending_edit and io_job.identity==cache_identity:
   image=Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RGBA8,result.pixels)
   displayed=Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RGBA8,atlas.surface_pixels(result.pixels))
   dirty.clear();cache_hits+=1;cache_saved=true;atlas.texture.update(displayed);atlas.view.queue_redraw();atlas.status.text=description()
  io_job.clear()
 if upload_pending and (Time.get_ticks_msec()-last_upload>=200 or dirty.is_empty() and pending.is_empty()):
  atlas.texture.update(displayed);atlas.view.queue_redraw();upload_pending=false;last_upload=Time.get_ticks_msec()
 if not (atlas.opened or atlas.warming) or image==null:return
 if epoch!=terrain.epoch:return
 if not identity_checked:
  if not pending.is_empty():return
  serial+=1
  if terrain.request_survey_identity(serial):pending[serial]={"kind":"identity"}
  return
 if dirty.is_empty():
  if not pending.is_empty():return
  if not cache_saved and not cache_identity.is_empty() and cache_revision==terrain.density_revision and not terrain.pending_edit:
   cache_saved=true;io_job={"kind":"write"};io=Thread.new()
   if io.start(Cache.write.bind(terrain.save_slot,cache_identity,image.get_data(),Cache.ROOT,16,SIZE),Thread.PRIORITY_LOW)!=OK:io=null;io_job.clear();cache_saved=false
  return
 for tile:Vector2i in dirty.keys():
  if pending.size()>=clampi(in_flight_limit,1,4):break
  var rect:=Rect2i(tile*TILE,Vector2i(TILE,TILE));serial+=1
  if not terrain.request_survey_patch(rect,serial,SIZE):break
  dirty.erase(tile);pending[serial]={"kind":"patch","tile":tile}
func receive(result:Dictionary)->void:
 if not pending.has(result.token):return
 var job:Dictionary=pending[result.token];pending.erase(result.token)
 if job.kind=="identity":
  if result.epoch!=epoch or terrain.epoch!=epoch or result.revision!=terrain.density_revision or terrain.pending_edit:return
  identity_checked=true;cache_identity=result.identity;cache_revision=result.revision
  if not cache_identity.is_empty():
   io_job={"kind":"read","epoch":epoch,"revision":result.revision,"identity":cache_identity};io=Thread.new()
   if io.start(Cache.read.bind(terrain.save_slot,cache_identity,Cache.ROOT,SIZE),Thread.PRIORITY_LOW)!=OK:io=null;io_job.clear()
  return
 var tile:Vector2i=job.tile
 if result.epoch!=epoch or terrain.epoch!=epoch:return
 if not result.get("ok",false) or result.get("revision",-1)!=terrain.density_revision or terrain.pending_edit:
  dirty[tile]=true;return
 if image==null:return
 var patch:=Image.create_from_data(TILE,TILE,false,Image.FORMAT_RGBA8,result.pixels)
 image.blit_rect(patch,Rect2i(0,0,TILE,TILE),tile*TILE)
 displayed.blit_rect(Image.create_from_data(TILE,TILE,false,Image.FORMAT_RGBA8,atlas.surface_pixels(result.pixels,tile*TILE,TILE)),Rect2i(0,0,TILE,TILE),tile*TILE)
 upload_pending=true;patches+=1;max_native_ms=maxf(max_native_ms,result.generation_ms)
 atlas.status.text=description()

func description()->String:
 var count:=dirty.size()+pending.size()
 return ("Terrain survey updating (%d areas)"%count if count>0 else "Terrain surface surveyed")+" | "+atlas.water_survey.description()+" | "+atlas.block_survey.description()+" | "+atlas.model_survey.description()

func recheck_identity()->void:
 # An intervening save may have certified a previously unsaved terrain revision.
 if cache_identity.is_empty():identity_checked=false
func _exit_tree()->void:
 if io!=null:io.wait_to_finish();io=null
