# SPDX-License-Identifier: 0BSD
extends "res://addons/world_runtime/survey_overlay.gd"
var archive:RefCounted
var assets:Array=[]
var asset_cursor:=0
var batch:Node3D
var index:Dictionary={}
var checkpoint:PackedByteArray
var lease:=0
var ticket:=0
var region_cursor:=0
var after_id:=0
var decoded:RefCounted
var boxes:Array=[]
var projection_cursor:=Vector2i.ZERO
var region_complete:=false
var archived_reads:=0
func _ready()->void:
 serial=-3000000;image_size=512;tint=Color("bba0cf");caption="Objects"
 cache_namespace="model-map-v1-512";cache_root="user://cartography/models"
 super._ready()
func current_stamp()->String:
 var parts:=PackedStringArray(["%d/%d"%[terrain.epoch,terrain.density_revision]])
 var names:Array=atlas.game.structures._models.keys();names.sort()
 for name in names:
  var source=atlas.game.structures._models[name]
  parts.append("%s/%d/%d/%s/%s"%[name,source.get_instance_id(),source.survey_revision_id(),str(source.global_transform),str(source.survey_prototype_bounds())])
 return "|".join(parts)
func begin_source()->void:
 archive=terrain.backend.snapshot_codec;assets=atlas.game.structures._models.keys();assets.sort()
 asset_cursor=0;index={};boxes=[];decoded=null;region_cursor=0;after_id=0
func stop_source()->void:
 if archive!=null:
  if ticket>0:archive.discard_survey_region_read(ticket)
  if lease>0:archive.release_read_checkpoint(lease)
 ticket=0;lease=0;decoded=null;boxes=[]
func source_step()->Dictionary:
 var empty:={"ok":true,"points":PackedVector3Array(),"complete":false}
 if asset_cursor>=assets.size():stop_source();empty.complete=true;return empty
 if index.is_empty():
  batch=atlas.game.structures._models[assets[asset_cursor]]
  index=batch.survey_index()
  if not index.get("ready",false):index={};return {"available":false}
  checkpoint=atlas.game.structures._model_checkpoints.get(assets[asset_cursor],PackedByteArray())
  if checkpoint.is_empty():checkpoint=archive.published_model_index(assets[asset_cursor]).get("checkpoint",PackedByteArray())
  region_cursor=0;after_id=0
 if region_cursor>=index.keys.size()/3:
  stop_source();index={};asset_cursor+=1;empty.complete=asset_cursor==assets.size();return empty
 if checkpoint.size()==32 and lease==0:
  lease=archive.retain_read_checkpoint(assets[asset_cursor],checkpoint)
  if lease==0:return {"available":false}
 if not boxes.is_empty():
  var projected:Dictionary=raster.project_bounds(boxes,index.transform,projection_cursor)
  if not projected.ok:return projected
  projection_cursor=projected.cursor
  if projected.complete:
   boxes=[]
   if region_complete:region_cursor+=1;after_id=0;decoded=null
  projected.complete=false
  return projected
 var key:=Vector3i(index.keys[region_cursor*3],index.keys[region_cursor*3+1],index.keys[region_cursor*3+2])
 var digest:PackedByteArray=index.checksums.slice(region_cursor*32,(region_cursor+1)*32)
 var absent:=PackedByteArray();absent.resize(32);absent.fill(0)
 if digest!=absent and decoded==null:
  if ticket==0:
   ticket=archive.request_model_survey_read(assets[asset_cursor],key,digest,checkpoint,epoch,index.prototype_bounds)
   return {"available":false}
  var reply:Dictionary=archive.take_survey_region_read(ticket)
  if reply.is_empty():return {"available":false}
  ticket=0
  if not reply.get("ok",false):return {"ok":false}
  decoded=reply.survey;archived_reads+=1
 var part:Dictionary=decoded.bounds(after_id) if decoded!=null else batch.survey_bounds(key,after_id,index.revision)
 if not part.get("ok",false):return part
 after_id=part.after_id;boxes=part.bounds;projection_cursor=Vector2i.ZERO;region_complete=part.complete
 if boxes.is_empty() and region_complete:region_cursor+=1;after_id=0;decoded=null
 return empty
