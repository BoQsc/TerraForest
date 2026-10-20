# SPDX-License-Identifier: 0BSD
extends Node
# Only bounded orchestration here; native code owns reduction and density work.
var atlas:Node
var terrain:Node
var texture:ImageTexture
var raster:RefCounted
var stamp:=""
var water:RefCounted
var epoch:=-1
var terrain_revision:=-1
var water_revision:=-1
var cursor:=0
var offset:=0
var source_done:=false
var complete:=false
var pending:=false
var serial:=-1000000
var source_calls:=0
var visibility_calls:=0
var max_source_us:=0
var max_visibility_ms:=0.0
var builds:=0
const Cache=preload("res://addons/world_runtime/survey_patch_cache.gd")
const CACHE_ROOT:="user://cartography/water"
var source_hash:HashingContext
var source_signature:=""
var cache_key:=""
var cache_checked:=false
var cache_hits:=0
var cache_writes:=0
var io:Thread
var io_stamp:=""
var io_kind:=""
func _ready()->void:
 terrain=atlas.game.terrain;terrain.survey_patch_ready.connect(receive)
 set_process(false)
func current_stamp()->String:
 var store=atlas.game.lakes.water
 if store==null:return ""
 return "%d/%d/%d/%d"%[terrain.epoch,terrain.density_revision,store.get_instance_id(),store.survey_revision_id()]
func restart(value:String)->void:
 stamp=value;water=atlas.game.lakes.water;epoch=terrain.epoch;terrain_revision=terrain.density_revision;water_revision=water.survey_revision_id()
 texture=null;raster=ClassDB.instantiate("NativeWaterMapRaster");cursor=0;offset=0;source_done=false;complete=false;pending=false;builds+=1
 source_hash=HashingContext.new();source_hash.start(HashingContext.HASH_SHA256);source_signature="";cache_checked=false;cache_key=""
 atlas.view.queue_redraw()
func _process(_delta:float)->void:
 if io!=null:
  if io.is_alive():return
  var reply:Dictionary=io.wait_to_finish();io=null
  if io_kind=="write":
   if reply.get("persisted",false):cache_writes+=1
  elif reply.get("hit",false) and io_stamp==stamp and current_stamp()==stamp and not terrain.pending_edit:
   publish(reply.pixels);cache_hits+=1
 if not atlas.opened or not terrain.world_ready or terrain.pending_edit:return
 var next:=current_stamp()
 if next.is_empty():return
 if next!=stamp:restart(next)
 if complete or pending:return
 if not source_done:
  var began:=Time.get_ticks_usec()
  for n in 4:
   var result:Dictionary=water.survey_surfaces(cursor,water_revision,4)
   if not result.get("ok",false) or not result.get("ready",false):stamp="";return
   if not raster.offer(result.points):stamp="";return
   if not result.points.is_empty():source_hash.update(result.points.to_byte_array())
   cursor=result.cursor;source_done=result.complete;source_calls+=1;max_source_us=maxi(max_source_us,result.worker_us)
   if source_done or Time.get_ticks_usec()-began>=1000:break
  if source_done:source_signature=source_hash.finish().hex_encode()
  atlas.status.text=atlas.updates.description()
  return
 if not cache_checked:
  if not atlas.updates.identity_checked:return
  cache_checked=true
  if not atlas.updates.cache_identity.is_empty() and atlas.updates.cache_revision==terrain_revision:
   cache_key="water-map-v1|"+atlas.updates.cache_identity+"|"+source_signature
   io_stamp=stamp;io_kind="read";io=Thread.new()
   if io.start(Cache.read.bind(cache_key,cache_key,CACHE_ROOT),Thread.PRIORITY_LOW)!=OK:io=null
   else:return
 if offset<raster.count():
  serial-=1
  if terrain.request_water_visibility(raster.batch(offset),serial):pending=true
  return
 var pixels:PackedByteArray=raster.pixels();publish(pixels)
 if not cache_key.is_empty():
  io_stamp=stamp;io_kind="write";io=Thread.new()
  if io.start(Cache.write.bind(cache_key,cache_key,pixels,CACHE_ROOT),Thread.PRIORITY_LOW)!=OK:io=null
func publish(pixels:PackedByteArray)->void:
 texture=ImageTexture.create_from_image(Image.create_from_data(256,256,false,Image.FORMAT_RGBA8,pixels))
 complete=true;atlas.view.queue_redraw();atlas.status.text=atlas.updates.description()
func receive(result:Dictionary)->void:
 if not pending or result.get("kind","")!="survey_water_visibility" or result.token!=serial:return
 pending=false
 if result.epoch!=epoch or result.get("revision",-1)!=terrain_revision or current_stamp()!=stamp:stamp="";return
 if not result.get("ok",false) or not raster.accept(offset,result.visible):stamp="";return
 offset+=result.visible.size();visibility_calls+=1;max_visibility_ms=maxf(max_visibility_ms,result.generation_ms)
func description()->String:
 return "Water surveyed" if complete else "Water survey updating…"

func _exit_tree()->void:
 if io!=null:io.wait_to_finish();io=null
