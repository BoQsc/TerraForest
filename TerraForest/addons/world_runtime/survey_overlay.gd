# SPDX-License-Identifier: 0BSD
extends Node
# Only bounded orchestration here; native code owns reduction and density work.
var atlas:Node
var terrain:Node
var texture:ImageTexture
var drawing_texture:Texture2D
var raster:RefCounted
var stamp:=""
var epoch:=-1
var terrain_revision:=-1
var offset:=0
var source_done:=false
var complete:=false
var failed:=false
var pending:=false
var serial:=-1000000
var source_calls:=0
var visibility_calls:=0
var max_source_us:=0
var max_visibility_ms:=0.0
var builds:=0
const Cache=preload("res://addons/world_runtime/survey_patch_cache.gd")
var cache_root:="user://cartography/water"
var cache_namespace:="water-map-v1"
var image_size:=256
var tint:=Color(54/255.0,117/255.0,140/255.0)
var caption:="Water"
var source_hash:HashingContext
var source_signature:=""
var cache_key:=""
var cache_checked:=false
var fast_checked:=false
var fast_cache_hits:=0
var cache_hits:=0
var cache_writes:=0
var io:Thread
var io_stamp:=""
var io_kind:=""
func _ready()->void:
 terrain=atlas.game.terrain;terrain.survey_patch_ready.connect(receive)
 set_process(false)
func current_stamp()->String:return ""
func fast_identity()->String:return ""
func begin_source()->void:pass
func stop_source()->void:pass
func source_step()->Dictionary:return {"available":false}
func restart(value:String)->void:
 stop_source();stamp=value;epoch=terrain.epoch;terrain_revision=terrain.density_revision
 texture=null;drawing_texture=null;raster=ClassDB.instantiate("NativeSurfaceMapRaster");raster.configure(image_size);offset=0;source_done=false;complete=false;failed=false;pending=false;builds+=1
 source_hash=HashingContext.new();source_hash.start(HashingContext.HASH_SHA256);source_signature="";cache_checked=false;fast_checked=false;cache_key=""
 begin_source();atlas.view.queue_redraw()
func _process(_delta:float)->void:
 if io!=null:
  if io.is_alive():return
  var reply:Dictionary=io.wait_to_finish();io=null
  if io_kind=="write":
   if reply.get("persisted",false):cache_writes+=1
  elif reply.get("hit",false) and io_stamp==stamp and current_stamp()==stamp and not terrain.pending_edit:
   publish(reply.pixels);cache_hits+=1
   if io_kind=="fast_read":fast_cache_hits+=1
 if not atlas.opened or not terrain.world_ready or terrain.pending_edit:return
 var next:=current_stamp()
 if next.is_empty():return
 if next!=stamp:restart(next)
 if complete or failed or pending:return
 if not fast_checked:
  if not atlas.updates.identity_checked:return
  fast_checked=true
  var certified:=fast_identity()
  if not certified.is_empty() and not atlas.updates.cache_identity.is_empty() and atlas.updates.cache_revision==terrain_revision:
   cache_key=cache_namespace+"|certified|"+atlas.updates.cache_identity+"|"+certified;cache_checked=true
   io_stamp=stamp;io_kind="fast_read";io=Thread.new()
   if io.start(Cache.read.bind(cache_key,cache_key,cache_root,image_size),Thread.PRIORITY_LOW)!=OK:io=null
   else:return
 if not source_done:
  var began:=Time.get_ticks_usec()
  for n in 4:
   var result:Dictionary=source_step()
   if not result.get("available",true):return
   if result.get("stale",false) or not result.get("ready",true):stamp="";return
   if not result.get("ok",false):fail_survey();return
   if not raster.offer(result.points):fail_survey();return
   if not result.points.is_empty():source_hash.update(result.points.to_byte_array())
   source_done=result.complete;source_calls+=1;max_source_us=maxi(max_source_us,result.get("worker_us",0))
   if source_done or Time.get_ticks_usec()-began>=1000:break
  if source_done:source_signature=source_hash.finish().hex_encode()
  atlas.status.text=atlas.updates.description()
  return
 if not cache_checked:
  if not atlas.updates.identity_checked:return
  cache_checked=true
  if not atlas.updates.cache_identity.is_empty() and atlas.updates.cache_revision==terrain_revision:
   cache_key=cache_namespace+"|"+atlas.updates.cache_identity+"|"+source_signature
   io_stamp=stamp;io_kind="read";io=Thread.new()
   if io.start(Cache.read.bind(cache_key,cache_key,cache_root,image_size),Thread.PRIORITY_LOW)!=OK:io=null
   else:return
 if offset<raster.count():
  serial-=1
  if terrain.request_water_visibility(raster.batch(offset),serial):pending=true
  return
 var pixels:PackedByteArray=raster.pixels(tint);publish(pixels)
 if not cache_key.is_empty():
  io_stamp=stamp;io_kind="write";io=Thread.new()
  if io.start(Cache.write.bind(cache_key,cache_key,pixels,cache_root,16 if image_size==512 else 64,image_size),Thread.PRIORITY_LOW)!=OK:io=null
func publish(pixels:PackedByteArray)->void:
 texture=ImageTexture.create_from_image(Image.create_from_data(image_size,image_size,false,Image.FORMAT_RGBA8,pixels))
 drawing_texture=texture
 if image_size==512:
  var canvas:=CanvasTexture.new();canvas.diffuse_texture=texture;canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;drawing_texture=canvas
 complete=true;atlas.view.queue_redraw();atlas.status.text=atlas.updates.description()
func receive(result:Dictionary)->void:
 if not pending or result.get("kind","")!="survey_water_visibility" or result.token!=serial:return
 pending=false
 if result.epoch!=epoch or result.get("revision",-1)!=terrain_revision or current_stamp()!=stamp:stamp="";return
 if not result.get("ok",false) or not raster.accept(offset,result.visible):fail_survey();return
 offset+=result.visible.size();visibility_calls+=1;max_visibility_ms=maxf(max_visibility_ms,result.generation_ms)
func fail_survey()->void:
 failed=true;stop_source();atlas.status.text=atlas.updates.description()
func description()->String:
 if failed:return caption+" survey unavailable"
 return caption+(" surveyed" if complete else " survey updating…")

func pause()->void:
 if not complete:stop_source();stamp="";pending=false
func _exit_tree()->void:
 stop_source()
 if io!=null:io.wait_to_finish();io=null
