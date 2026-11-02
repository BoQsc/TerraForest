# SPDX-License-Identifier: 0BSD
extends SceneTree

class Game extends Node:
	var terrain:Dictionary

class ProbeCache extends "res://addons/volumetric_terrain/derived_cache.gd":
	var slices:=0
	var during:Callable
	func accounting_pending()->bool:return slices<3
	func advance_accounting()->void:
		slices+=1
		if during.is_valid():during.call()

var checks:=0
var failures:=0

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func _initialize()->void:
	var backend=load("res://addons/volumetric_terrain/terrain_backend.gd").new()
	var game:=Game.new()
	game.terrain={"backend":backend,"pending_edit":false,"_manual_save_requested":false}
	var reset=load("res://addons/world_runtime/location_reset_live.gd").new();reset.game=game
	check(reset._idle(),"idle world admits reset checkpoint")
	for state:String in ["mesh","edit","load","save","republish","lake_slice","density_batch","material_edit"]:
		backend.active_kind=state
		check(not reset._idle(),"checkpoint still waits for active "+state)
	backend.active_kind="cache_accounting"
	check(reset._idle(),"background cache accounting does not block checkpoint admission")
	backend.jobs.append({"kind":"edit"})
	check(not reset._idle(),"cache accounting never bypasses queued work");backend.jobs.clear()
	backend._save_reserved=true
	check(not reset._idle(),"cache accounting never bypasses pending publication");backend._save_reserved=false
	game.terrain.pending_edit=true
	check(not reset._idle(),"cache accounting never bypasses unpublished terrain edits");game.terrain.pending_edit=false
	game.terrain._manual_save_requested=true
	check(not reset._idle(),"cache accounting never overtakes an existing manual save");game.terrain._manual_save_requested=false
	var cache:=ProbeCache.new();backend.disk_cache=cache
	cache.during=func():
		if reset._idle():backend.submit({"kind":"save"})
	backend._advance_cache_when_idle()
	check(cache.slices==1 and backend.jobs.size()==1 and backend.publication_pending(),"checkpoint submission preempts cache accounting after one bounded slice")
	check(not reset._idle(),"submitted checkpoint holds the normal publication barrier")
	backend.jobs.clear();backend._save_reserved=false;cache.during=Callable()
	backend._advance_cache_when_idle()
	check(cache.slices==3 and backend.active_kind=="idle","cache accounting resumes after checkpoint completion")
	reset.free();game.free()
	print("LOCATION_RESET_ADMISSION checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
