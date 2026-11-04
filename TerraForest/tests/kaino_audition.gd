# SPDX-License-Identifier: 0BSD
extends SceneTree
var audition:Control
var checks:=0
var failures:=0

func _initialize()->void:run.call_deferred()
func check(condition:bool,message:String)->bool:
	checks+=1
	if not condition:failures+=1
	print("PASS " if condition else "FAIL ",message)
	return condition
func run()->void:
	audition=load("res://tools/kaino_audition.tscn").instantiate()
	audition.mapping_path="user://kaino_audition_test.json"
	root.add_child(audition)
	await process_frame
	await process_frame
	check(audition.files.size()>0,"Kaino WAV files discovered")
	check(audition.slots.size()>0,"actual game sound slots loaded")
	if audition.files.is_empty() or audition.slots.is_empty():
		await finish()
		return
	audition.select_file(audition.files[0],true)
	await create_timer(.15).timeout
	check(audition.audio_player.stream!=null and audition.audio_player.playing,"selected Kaino file starts playback")
	audition.select_slot(str(audition.slots[0].id))
	audition.assign_selected()
	check(str(audition.mapping.get(audition.selected_slot,""))==audition.files[0],"selected slot records selected file")
	audition.save_mapping()
	await process_frame
	check(FileAccess.file_exists(ProjectSettings.globalize_path(audition.mapping_path)),"selection mapping is written")
	var catalog=preload("res://addons/audio_runtime/catalog.gd").new()
	var prepared:bool=catalog.prepare(PackedStringArray(["res://addons/audio_runtime/packs/nox/pack.audio.module.json"]))
	var applied:int=preload("res://addons/audio_runtime/kaino_audition_map.gd").apply(catalog,audition.mapping_path) if prepared else 0
	var resolved:Dictionary=catalog.resolve("movement.footstep", {"surface":"dirt","gait":"walk"})
	check(prepared and applied>0 and resolved.has("files") and catalog.streams.has(resolved.files[0]),"saved mapping substitutes the live event stream")
	var image:=root.get_texture().get_image()
	var folder:=ProjectSettings.globalize_path("res://reports/kaino_audition")
	DirAccess.make_dir_recursive_absolute(folder)
	image.save_png(folder.path_join("kaino_audition.png"))
	print("KAINO_AUDITION_CAPTURED reports/kaino_audition/kaino_audition.png")
	await finish()
func finish()->void:
	if is_instance_valid(audition):
		audition.stop_audio()
		audition.audio_player.stream=null
		await process_frame
		audition.free()
	await process_frame
	print("KAINO_AUDITION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
