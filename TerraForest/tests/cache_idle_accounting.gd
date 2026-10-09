# SPDX-License-Identifier: 0BSD
extends SceneTree
class ProbeCache extends "res://addons/volumetric_terrain/derived_cache.gd":
	var slices:=0
	var during: Callable
	func accounting_pending() -> bool:return slices<3
	func advance_accounting() -> void:
		slices+=1
		if during.is_valid():during.call()
func _initialize() -> void:
	var backend=load("res://addons/volumetric_terrain/terrain_backend.gd").new()
	var cache:=ProbeCache.new();backend.disk_cache=cache
	backend.jobs.append({"kind":"mesh"});backend._advance_cache_when_idle()
	var ok: bool=cache.slices==0
	backend.jobs.clear();backend.active_input=true;backend._advance_cache_when_idle();ok=ok and cache.slices==0
	backend.active_input=false;backend.stopping=true;backend._advance_cache_when_idle();ok=ok and cache.slices==0
	backend.stopping=false
	cache.during=func():backend.jobs.append({"kind":"edit"})
	backend._advance_cache_when_idle()
	ok=ok and cache.slices==1 and backend.active_kind=="idle" and backend.results.size()==1
	cache.during=Callable();backend.jobs.clear();backend._advance_cache_when_idle()
	ok=ok and cache.slices==3 and backend.active_kind=="idle" and backend.results.size()==2
	print("CACHE_IDLE queued/input/stop guards, slice preemption and resumption=",ok)
	quit(0 if ok else 1)
