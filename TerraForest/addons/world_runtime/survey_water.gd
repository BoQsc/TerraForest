# SPDX-License-Identifier: 0BSD
extends "res://addons/world_runtime/survey_overlay.gd"
var water:RefCounted
var water_revision:=-1
var cursor:=0
func current_stamp()->String:
 var store=atlas.game.lakes.water
 if store==null:return ""
 return "%d/%d/%d/%d"%[terrain.epoch,terrain.density_revision,store.get_instance_id(),store.survey_revision_id()]
func fast_identity()->String:
 return water.survey_cache_identity() if water!=null else ""
func begin_source()->void:
 water=atlas.game.lakes.water;water_revision=water.survey_revision_id();cursor=0
func source_step()->Dictionary:
 var result:Dictionary=water.survey_surfaces(cursor,water_revision,4)
 if result.get("ok",false):cursor=result.cursor
 return result
