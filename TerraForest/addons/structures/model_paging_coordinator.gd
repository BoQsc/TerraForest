# SPDX-License-Identifier: 0BSD
extends Node
## Lifecycle glue only. Selection, storage, transfers and spatial indexing are native.
var terrain: Node3D
var structures: Node3D
var history: RefCounted
var focus: Callable
var operation := ""
var waiting_save := false
var last_state: Dictionary = {"active":false}
var save_completions := 0
var successful_saves := 0
var attached := false

func attach(world: Node3D, buildings: Node3D, journal: RefCounted, focus_source: Callable) -> bool:
	if attached or world.lifecycle_ready.is_valid() or world.backend.snapshot_ready.is_valid() or not focus_source.is_valid():
		return false
	terrain=world;structures=buildings;history=journal;focus=focus_source
	terrain.lifecycle_ready=ready_for
	terrain.backend.snapshot_ready=ready_for
	terrain.backend.snapshot_save_submitted.connect(_save_submitted)
	terrain.save_completed.connect(_save_completed)
	terrain.snapshot_restored.connect(_restored)
	process_priority=-5
	attached=true
	return true

func ready_for(kind: String) -> bool:
	if kind=="save":
		if operation not in ["","save"] or waiting_save:return false
		operation="save"
	else:
		if operation=="shutdown" and kind!="shutdown":return false
		operation=kind
		if waiting_save:return false
	if not structures.drain_model_paging():return false
	if kind in ["reload","reset","shutdown"]:
		return structures.finish_model_paging()
	return true

func _save_submitted() -> void:
	waiting_save=true

func _save_completed(success: bool) -> void:
	waiting_save=false
	save_completions+=1
	if success:successful_saves+=1
	if operation=="save":operation="resume"

func _restored(_sections: Dictionary, _epoch: int) -> void:
	if operation!="shutdown":operation=""

func _process(_delta: float) -> void:
	if not attached or terrain.stopping:return
	var archive: RefCounted=terrain.backend.snapshot_codec
	if terrain.world_ready and not terrain.closing and operation=="" and structures._model_scheduler==null:
		if not archive.region_read_stats().running and not archive.start_region_reads(16,64*1024*1024):return
		if not structures.enable_region_paging(archive):return
		if not structures.enable_model_paging(archive,history):return
	if structures._model_scheduler!=null:
		last_state=structures.step_model_paging(focus.call())
	if operation=="resume":
		if structures._model_scheduler==null or structures.resume_model_paging():operation=""

func _exit_tree() -> void:
	if not attached or not is_instance_valid(terrain):return
	if not terrain.stopping and not ready_for("shutdown"):
		terrain.backend.disable_snapshot_writes("paging coordinator removed before transfers drained")
	if terrain.lifecycle_ready==ready_for:terrain.lifecycle_ready=Callable()
	if terrain.backend.snapshot_ready==ready_for:terrain.backend.snapshot_ready=Callable()
