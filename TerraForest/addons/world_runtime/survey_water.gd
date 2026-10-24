# SPDX-License-Identifier: 0BSD
extends "res://addons/world_runtime/survey_overlay.gd"
var water:RefCounted
var water_revision:=-1
var cursor:=0
var ocean_cursor:=0
var ocean_done:=false
func current_stamp()->String:
 var store=atlas.game.lakes.water
 if store==null:return ""
 return "%d/%d/%d/%d"%[terrain.epoch,terrain.density_revision,store.get_instance_id(),store.survey_revision_id()]
func fast_identity()->String:
 return water.survey_cache_identity() if water!=null and terrain.backend.world_generator not in [19,21] else ""
func begin_source()->void:
 water=atlas.game.lakes.water;water_revision=water.survey_revision_id();cursor=0;ocean_cursor=0;ocean_done=terrain.backend.world_generator not in [19,21]
 batch_limit=256 if not ocean_done else 16
 cache_namespace="water-map-v2"
func source_step()->Dictionary:
 if not ocean_done:
  var sea:Dictionary=water.survey_ocean(ocean_cursor,water_revision)
  if sea.get("ok",false):ocean_cursor=sea.cursor;ocean_done=sea.complete;sea.complete=false
  return sea
 var result:Dictionary=water.survey_surfaces(cursor,water_revision,4)
 if result.get("ok",false):cursor=result.cursor
 return result
