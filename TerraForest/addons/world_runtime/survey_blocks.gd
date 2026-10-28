# SPDX-License-Identifier: 0BSD
extends "res://addons/world_runtime/survey_overlay.gd"
var blocks:Node3D
var archive:RefCounted
var index:Dictionary
var checkpoint:PackedByteArray
var lease:=0
var ticket:=0
var region_cursor:=0
var chunk_cursor:=0
var decoded:RefCounted
var archived_reads:=0
func _ready()->void:
 serial=-2000000;image_size=512;tint=Color("d9c9ad");caption="Blocks"
 cache_namespace="block-map-material-v2-512";cache_root="user://cartography/blocks"
 super._ready()
func current_stamp()->String:
 var source=atlas.game.structures.blocks
 var identity:String=source.survey_cache_identity()
 var content:String=identity if not identity.is_empty() else str(source.survey_content_revision_id())
 return "%d/%d/%d/%s/%s"%[terrain.epoch,terrain.density_revision,source.get_instance_id(),content,var_to_bytes(source.global_transform).hex_encode()]
func fast_identity()->String:
 var identity:String=atlas.game.structures.blocks.survey_cache_identity()
 return identity+"|"+var_to_bytes(atlas.game.structures.blocks.global_transform).hex_encode() if not identity.is_empty() else ""
func begin_source()->void:
 blocks=atlas.game.structures.blocks;archive=terrain.backend.snapshot_codec;index={};checkpoint=atlas.game.structures._storage_checkpoint
 region_cursor=0;chunk_cursor=0;decoded=null
 # Capture region metadata only after an early cache miss.
func stop_source()->void:
 if archive!=null:
  if ticket>0:archive.discard_survey_region_read(ticket)
  if lease>0:archive.release_read_checkpoint(lease)
 ticket=0;lease=0;decoded=null
func source_step()->Dictionary:
 if index.is_empty():index=blocks.survey_index()
 if region_cursor>=index.keys.size()/3:
  stop_source();return {"ok":true,"points":PackedVector3Array(),"complete":true}
 if checkpoint.size()==32 and lease==0:
  lease=archive.retain_read_checkpoint("",checkpoint)
  if lease==0:return {"available":false}
 var key:=Vector3i(index.keys[region_cursor*3],index.keys[region_cursor*3+1],index.keys[region_cursor*3+2])
 var digest:PackedByteArray=index.checksums.slice(region_cursor*32,(region_cursor+1)*32)
 var absent:=PackedByteArray();absent.resize(32);absent.fill(0)
 if digest!=absent and decoded==null:
  if ticket==0:
   ticket=archive.request_survey_region_read(key,digest,checkpoint,epoch)
   return {"available":false}
  var reply:Dictionary=archive.take_survey_region_read(ticket)
  if reply.is_empty():return {"available":false}
  ticket=0
  if not reply.get("ok",false):return {"ok":false}
  decoded=reply.survey;archived_reads+=1
 var began:=Time.get_ticks_usec()
 var part:Dictionary=decoded.columns(chunk_cursor) if decoded!=null else blocks.survey_columns(key,chunk_cursor,index.revision)
 if not part.get("ok",false):return part
 chunk_cursor=part.offset
 if part.complete:region_cursor+=1;chunk_cursor=0;decoded=null
 part.points=index.transform*part.points;part.complete=region_cursor>=index.keys.size()/3;part.worker_us=Time.get_ticks_usec()-began
 if part.complete:stop_source()
 return part
