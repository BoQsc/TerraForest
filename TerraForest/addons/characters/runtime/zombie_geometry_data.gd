# SPDX-License-Identifier: 0BSD
extends Resource
## Immutable CPU mesh data for a declared model; mutable anatomy stays per actor.
@export var source_model:PackedScene:
	set(value):
		source_model=value
		_cache=null
		_invalidated=false
		_refresh_needed=false
		if value==null:return
		# Watch the imported resources as soon as the bundle loads, including
		# edits before its first actor. SceneState access creates no scene nodes.
		var state:=value.get_state()
		for node in state.get_node_count():
			for property in state.get_node_property_count(node):
				var resource:Variant=state.get_node_property_value(node,property)
				if resource is Mesh or resource is Skin:
					if not resource.changed.is_connected(_source_changed):resource.changed.connect(_source_changed)
@export var data:Dictionary={}
var _cache:RefCounted
var _invalidated:=false
var _refresh_needed:=false
var last_prepare_us:=0
var last_readback_us:=0

func _source_changed()->void:
	_invalidated=true
	_refresh_needed=true
	# Keep the previous native listener alive until this signal emission ends.
	# Preparation replaces it later, after all asset invalidation callbacks run.

func statistics()->Dictionary:
	var result:Dictionary=_cache.geometry_stats() if _cache!=null else {}
	result["invalidated"]=_invalidated
	result["preparation_us"]=last_prepare_us
	return result

func prepare(skeleton:Skeleton3D,meshes:Dictionary,definitions:Dictionary)->RefCounted:
	last_prepare_us=0;last_readback_us=0
	if _cache!=null and not _refresh_needed and _cache.geometry_stats().valid:return _cache
	var began:=Time.get_ticks_usec()
	var next:RefCounted=ClassDB.instantiate("NativeZombieAnatomy")
	if next==null or not next.configure(definitions):return null
	if not next.set_hit_meshes(skeleton,meshes,null,{} if _invalidated else data):return null
	if next.fit_collision_shapes().size()!=15:return null
	last_readback_us=next.geometry_stats().readback_us
	last_prepare_us=Time.get_ticks_usec()-began
	_cache=next
	_refresh_needed=false
	return _cache
