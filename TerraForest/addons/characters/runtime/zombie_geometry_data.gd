# SPDX-License-Identifier: 0BSD
extends Resource
## Immutable CPU mesh data for a declared model; mutable anatomy stays per actor.
@export var source_model:PackedScene:
	set(value):
		source_model=value
		_cache=null
		_invalidated=false
		_refresh_needed=false
		_render_sources.clear()
		if value==null:return
		# Watch the imported resources as soon as the bundle loads, including
		# edits before its first actor. SceneState access creates no scene nodes.
		var state:=value.get_state()
		for node in state.get_node_count():
			for property in state.get_node_property_count(node):
				var resource:Variant=state.get_node_property_value(node,property)
				if resource is Mesh or resource is Skin:
					if not resource.changed.is_connected(_source_changed):resource.changed.connect(_source_changed)
					if resource is Mesh:_render_sources[resource.resource_path]=resource
@export var data:Dictionary={}
@export var render_packets:Dictionary={}
var _render_sources:Dictionary={}
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

func render_packet(mesh:Mesh)->Dictionary:
	# A duplicate can inherit a resource path without being the declared source.
	if _invalidated or _render_sources.get(mesh.resource_path)!=mesh:return {}
	var packet:Dictionary=render_packets.get(mesh.resource_path,{})
	var surfaces:int=mesh.get_surface_count()
	if packet.get("surfaces",[]).size()!=surfaces or packet.get("morphs",[]).size()!=surfaces or packet.get("formats",[]).size()!=surfaces:return {}
	for surface in surfaces:
		var arrays:Array=packet.surfaces[surface]
		if arrays.size()!=Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:return {}
		if arrays[Mesh.ARRAY_VERTEX].size()!=mesh.surface_get_array_len(surface):return {}
		if packet.morphs[surface].size()!=mesh.get_blend_shape_count():return {}
		if mesh is ArrayMesh and packet.formats[surface]!=(mesh.surface_get_format(surface)&(4095<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)):return {}
	return packet

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
