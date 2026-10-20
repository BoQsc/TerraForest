# SPDX-License-Identifier: 0BSD
extends Node
# Bounded presentation queue; all density evaluation stays on the native worker.
var atlas:Node
var terrain:Node
var image:Image
var dirty:Dictionary={}
var pending:Dictionary={}
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

func _ready()->void:
 terrain=atlas.game.terrain
 terrain.region_changed.connect(changed)
 terrain.survey_patch_ready.connect(receive)
 set_process(false)
func reset()->void:
 epoch=terrain.epoch;image=null;dirty.clear();pending.clear()
 identity_checked=false;cache_identity="";cache_revision=-1;cache_saved=false
 for cell:Vector2i in terrain.modified_columns:
  changed(AABB(Vector3(cell.x*16,0,cell.y*16),Vector3(16,256,16)),0)
func changed(bounds:AABB,_revision:int)->void:
 identity_checked=false;cache_identity="";cache_saved=false
 var low:=Vector2i(floori((bounds.position.x-8)*256/2000/4),floori((bounds.position.z-8)*256/2000/4)).clamp(Vector2i.ZERO,Vector2i(63,63))
 var high:=Vector2i(floori((bounds.end.x+8)*256/2000/4),floori((bounds.end.z+8)*256/2000/4)).clamp(Vector2i.ZERO,Vector2i(63,63))
 for z in range(low.y,high.y+1):
  for x in range(low.x,high.x+1):dirty[Vector2i(x,z)]=true
func _process(_delta:float)->void:
 if io!=null:
  if io.is_alive():return
  var result:Dictionary=io.wait_to_finish();io=null
  if io_job.kind=="write":
   if result.get("persisted",false):cache_writes+=1
  elif result.get("hit",false) and image!=null and io_job.epoch==epoch and terrain.epoch==epoch and io_job.revision==terrain.density_revision and not terrain.pending_edit and io_job.identity==cache_identity:
   image=Image.create_from_data(256,256,false,Image.FORMAT_RGBA8,result.pixels)
   dirty.clear();cache_hits+=1;cache_saved=true;atlas.texture.update(image);atlas.view.queue_redraw();atlas.status.text=description()
  io_job.clear()
 if not atlas.opened or image==null or not pending.is_empty():return
 if epoch!=terrain.epoch:return
 if not identity_checked:
  serial+=1
  if terrain.request_survey_identity(serial):pending={"kind":"identity","token":serial}
  return
 if dirty.is_empty():
  if not cache_saved and not cache_identity.is_empty() and cache_revision==terrain.density_revision and not terrain.pending_edit:
   cache_saved=true;io_job={"kind":"write"};io=Thread.new()
   if io.start(Cache.write.bind(terrain.save_slot,cache_identity,image.get_data()),Thread.PRIORITY_LOW)!=OK:io=null;io_job.clear();cache_saved=false
  return
 var tile:Vector2i=dirty.keys()[0]
 var rect:=Rect2i(tile*4,Vector2i(4,4));serial+=1
 if terrain.request_survey_patch(rect,serial):
  dirty.erase(tile);pending={"kind":"patch","tile":tile,"token":serial}
func receive(result:Dictionary)->void:
 if pending.is_empty() or result.token!=pending.token:return
 if pending.kind=="identity":
  pending.clear()
  if result.epoch!=epoch or terrain.epoch!=epoch or result.revision!=terrain.density_revision or terrain.pending_edit:return
  identity_checked=true;cache_identity=result.identity;cache_revision=result.revision
  if not cache_identity.is_empty():
   io_job={"kind":"read","epoch":epoch,"revision":result.revision,"identity":cache_identity};io=Thread.new()
   if io.start(Cache.read.bind(terrain.save_slot,cache_identity),Thread.PRIORITY_LOW)!=OK:io=null;io_job.clear()
  return
 var tile:Vector2i=pending.tile;pending.clear()
 if result.epoch!=epoch or terrain.epoch!=epoch:return
 if not result.get("ok",false) or result.get("revision",-1)!=terrain.density_revision or terrain.pending_edit:
  dirty[tile]=true;return
 if image==null:return
 var patch:=Image.create_from_data(4,4,false,Image.FORMAT_RGBA8,result.pixels)
 image.blit_rect(patch,Rect2i(0,0,4,4),tile*4)
 atlas.texture.update(image);patches+=1;max_native_ms=maxf(max_native_ms,result.generation_ms)
 atlas.view.queue_redraw()
 atlas.status.text=description()

func description()->String:
 var count:=dirty.size()+(0 if pending.is_empty() else 1)
 return ("Terrain survey updating (%d areas)"%count if count>0 else "Terrain surface surveyed")+" | "+atlas.water_survey.description()+" | "+atlas.block_survey.description()

func recheck_identity()->void:
 # An intervening save may have certified a previously unsaved terrain revision.
 if cache_identity.is_empty():identity_checked=false
func _exit_tree()->void:
 if io!=null:io.wait_to_finish();io=null
