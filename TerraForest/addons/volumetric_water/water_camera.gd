# SPDX-License-Identifier: 0BSD
extends Node
## Camera-local presentation; uses ordinary depth fog, no extra render pass.
var camera: Camera3D
var lakes: Node3D
var underwater:=false
var _previous: Environment
var _submerged: Environment

func configure(view: Camera3D,water: Node3D) -> void:
	restore()
	camera=view
	lakes=water

func update() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(lakes):
		restore()
		return
	var depth: float=lakes.depth_at(camera.global_position)
	# Require a small entry margin but restore immediately outside occupancy.
	var wet: bool=depth>0.0 if underwater else depth>0.03
	if wet==underwater: return
	if not wet:
		restore()
		return
	_previous=camera.environment
	var source: Environment=_previous if _previous!=null else camera.get_world_3d().environment
	_submerged=source.duplicate() if source!=null else Environment.new()
	_submerged.background_mode=Environment.BG_COLOR
	_submerged.background_color=Color("103d49")
	_submerged.fog_enabled=true
	_submerged.fog_light_color=Color("286170")
	_submerged.fog_light_energy=0.65
	_submerged.fog_density=0.09
	_submerged.fog_sky_affect=1.0
	_submerged.volumetric_fog_enabled=false
	camera.environment=_submerged
	underwater=true

func restore() -> void:
	if underwater and is_instance_valid(camera) and camera.environment==_submerged:
		camera.environment=_previous
	underwater=false
	_submerged=null
	_previous=null

func _exit_tree() -> void:
	restore()
