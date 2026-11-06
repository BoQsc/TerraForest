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
	var test_path:=ProjectSettings.globalize_path(audition.mapping_path)
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(test_path+suffix): DirAccess.remove_absolute(test_path+suffix)
	var history:=DirAccess.open(ProjectSettings.globalize_path("user://kaino_audition_history"))
	if history!=null:
		for name:String in history.get_files(): history.remove(name)
	root.add_child(audition)
	await process_frame
	await process_frame
	check(audition.files.size()>0,"Kaino WAV files discovered")
	check(audition.slots.size()>0,"actual game sound slots loaded")
	check(audition.hide_occupied.button_pressed,"occupied slots are hidden by default")
	check(audition.slots.any(func(slot):return str(slot.id)=="vehicle.engine.loop") and audition.slots.any(func(slot):return str(slot.id)=="npc.zombie.attack"),"entity event catalog covers vehicles and NPCs")
	audition.select_file(audition.files[0],false)
	audition.notes_edit.text="Dry, short footstep for compacted dirt."
	audition.sync_note()
	check(audition.notes_edit!=null and audition.note_for(audition.files[0])=="Dry, short footstep for compacted dirt.","per-sound note is stored")
	audition.select_file(audition.files[1],false)
	await process_frame
	check(audition.file_boxes[audition.files[0]].visible and audition.file_rows[audition.files[0]].modulate.is_equal_approx(audition.NOTED_ROW_COLOR),"noted sound stays in the Sounds tab, painted blue")
	audition.set_sound_view("noted")
	check(audition.file_boxes[audition.files[0]].visible and audition.sound_noted_tab.text=="NOTED (1)","noted sound appears in the Noted tab")
	audition.set_sound_view("sounds")
	var deferred_path:String=audition.files[1]
	audition.file_later_buttons[deferred_path].pressed.emit()
	check(not audition.file_boxes[deferred_path].visible,"Later removes the selected pack sound from the main list")
	audition.set_sound_view(true)
	check(audition.file_boxes[deferred_path].visible and audition.sound_later_tab.text=="LATER (1)","deferred pack sound appears in the Later tab")
	audition.set_sound_view(false)
	audition.select_file(audition.files[0],false)
	await create_timer(.8).timeout
	var autosaved:Variant=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(audition.mapping_path)))
	check(autosaved is Dictionary and deferred_path in autosaved.get("deferred_sounds",[]),"defer action autosaves selection state")
	# Typing must stay in the notes field; the noted filter applies on leaving it.
	var typed_path:String=audition.files[4]
	audition.set_sound_view("sounds")
	audition.select_file(typed_path,false)
	audition.notes_edit.text=""
	audition.notes_edit.grab_focus()
	await process_frame
	for character in "dry":
		var typed:=InputEventKey.new()
		typed.unicode=character.unicode_at(0);typed.keycode=character.unicode_at(0);typed.physical_keycode=character.unicode_at(0);typed.pressed=true
		Input.parse_input_event(typed)
		await process_frame
	check(audition.notes_edit.text=="dry" and audition.selected_file==typed_path,"typing stays in the notes field")
	check(audition.file_boxes[typed_path].visible,"editing a note keeps the sound in the list")
	audition.notes_edit.release_focus()
	await process_frame
	audition.select_file(audition.files[5],false)
	await process_frame
	check(audition.file_boxes[typed_path].visible and audition.file_rows[typed_path].modulate.is_equal_approx(audition.NOTED_ROW_COLOR),"leaving the notes field keeps the sound listed in blue")
	check(audition.note_for(typed_path)=="dry","typed note is stored with the sound")
	var rejected_path:String=audition.files[2]
	audition.file_reject_buttons[rejected_path].pressed.emit()
	check(not audition.file_boxes[rejected_path].visible,"Not great removes the pack sound from the main list")
	audition.set_sound_view("rejected")
	check(audition.file_boxes[rejected_path].visible and audition.sound_rejected_tab.text=="NOT GREAT (1)","rejected pack sound appears in the Not great tab")
	audition.set_sound_view("sounds")
	audition.select_file(audition.files[0],false)
	if audition.files.is_empty() or audition.slots.is_empty():
		await finish()
		return
	audition.select_file(audition.files[0],true)
	await create_timer(.15).timeout
	check(audition.audio_player.stream!=null and audition.audio_player.playing,"selected Kaino file starts playback")
	var slot_id:String=audition.first_visible_slot()
	audition.select_slot(slot_id)
	check(not slot_id.is_empty() and audition.preview_model!=null,"selected event builds a looping mini-scene preview")
	check(audition.preview_animation_player!=null and audition.preview_animation_player.is_playing(),"mini-scene animation is running")
	audition.select_slot("vehicle.engine.loop")
	check(audition.preview_kind=="vehicle" and audition.preview_model!=null,"vehicle event builds a vehicle mini-scene")
	audition.select_slot("npc.zombie.attack")
	check(audition.preview_kind=="zombie" and audition.preview_model!=null and audition.preview_animation_player!=null,"NPC event builds an animated zombie mini-scene")
	audition.select_slot(slot_id)
	audition.assign_selected()
	check(str(audition.mapping.get(audition.selected_slot,""))==audition.files[0] and not audition.slot_rows[audition.selected_slot].visible,"selected slot records file and is hidden while occupied")
	# USED lists exactly the sounds chosen for a game event.
	audition.set_sound_view("used")
	check(audition.file_boxes[audition.files[0]].visible,"used tab shows the assigned sound")
	check(not audition.file_boxes[audition.files[3]].visible,"used tab hides sounds that are not assigned")
	check(audition.sound_used_tab.text=="USED (1)","used tab counts the chosen sounds")
	audition.set_sound_view("sounds")
	audition.hide_occupied.button_pressed=false
	audition.filter_slots()
	check(audition.slot_rows[audition.selected_slot].visible,"occupied slot can be revealed by toggle")
	audition.hide_occupied.button_pressed=true
	audition.filter_slots()
	# Staged introduction: a few noted sounds enter the game at a time.
	audition.notes[audition.files[7]]="great for pickaxe swing and mining stone"
	var staged:int=audition.introduce_stage(1)
	check(staged==1 and str(audition.mapping.get("tool.pickaxe.swing",""))==audition.files[7],"staged introduction assigns a noted sound to its slot")
	check(audition.used_files().has(audition.files[7]),"introduced sound counts as used")
	var again:int=audition.introduce_stage(1)
	check(again==0,"a stage never reuses a taken slot")
	audition.save_mapping()
	await process_frame
	check(FileAccess.file_exists(ProjectSettings.globalize_path(audition.mapping_path)),"selection mapping is written")
	var saved:Variant=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(audition.mapping_path)))
	check(saved is Dictionary and str(saved.get("notes",{}).get(audition.files[0],""))=="Dry, short footstep for compacted dirt.","note is persisted with the selection")
	check(saved is Dictionary and deferred_path in saved.get("deferred_sounds",[]),"deferred pack sound is persisted")
	check(saved is Dictionary and rejected_path in saved.get("rejected_sounds",[]),"rejected pack sound is persisted")
	check(FileAccess.file_exists(test_path+".bak"),"save keeps the previous selection as a backup")
	check(not FileAccess.file_exists(test_path+".tmp"),"atomic save leaves no temporary file behind")
	check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://kaino_audition_history")),"every save is recorded in the selection history")
	# An interrupted save must fall back to the backup instead of losing notes.
	audition.save_mapping(true)
	await process_frame
	audition.save_mapping(true)
	await process_frame
	FileAccess.open(test_path,FileAccess.WRITE).store_string("{ not json")
	audition.notes.clear();audition.mapping.clear();audition.deferred_sounds.clear();audition.rejected_sounds.clear()
	audition.load_mapping()
	check(audition.note_for(audition.files[0])=="Dry, short footstep for compacted dirt.","damaged selection file restores the backup note")
	var repaired:Variant=JSON.parse_string(FileAccess.get_file_as_string(test_path))
	check(repaired is Dictionary and audition.mapping.size()>0,"recovery rewrites a valid selection file")
	# Typing then waiting for autosave must reach disk without an explicit save.
	audition.select_file(audition.files[5],false)
	audition.notes_edit.text="autosaved note"
	audition.sync_note()
	await create_timer(0.4).timeout
	var live:Variant=JSON.parse_string(FileAccess.get_file_as_string(test_path))
	check(live is Dictionary and str(live.get("notes",{}).get(audition.files[5],""))=="autosaved note","notes reach disk through autosave alone")
	# Autosave must also run while the field still holds focus.
	audition.select_file(audition.files[6],false)
	audition.notes_edit.text="focused autosave"
	audition.notes_edit.grab_focus()
	audition.sync_note()
	await create_timer(0.4).timeout
	var focused_saved:Variant=JSON.parse_string(FileAccess.get_file_as_string(test_path))
	check(focused_saved is Dictionary and str(focused_saved.get("notes",{}).get(audition.files[6],""))=="focused autosave","autosave runs while the notes field keeps focus")
	audition.notes_edit.release_focus()
	await process_frame
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
