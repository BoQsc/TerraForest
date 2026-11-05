# SPDX-License-Identifier: 0BSD
extends Control
## Uses actual presentation modules, isolated from the world library and jobs.
var browser:Control
var loading:CanvasLayer
var current:=0
func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	browser=load("res://demo/worlds.gd").new();browser.preview_mode=true
	add_child(browser);browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	browser.worlds.add_item("Amber Bay · sample")
	browser.worlds.add_item("Bright Forest · sample")
	browser.saved_title.text="Amber Bay"
	browser.saved_details.text="Preview data · seed 1703\nSaved-world actions are disabled in this preview."
	browser.preview_due_ms=-1;browser.preview_status.text="Sample survey · planning disabled in preview"
	browser.seed_field.value=2
	browser.preview_view.texture=preload("res://addons/ui_sets/reference_media.gd").texture("res://demo/world_survey/assets/survey_map.png")
	if browser.preview_view.texture!=null:
		browser.preview_empty.hide();browser.preview_due_ms=-1
		browser.preview_metrics.text="Sample survey · seed 2 · no live planning job"
	loading=load("res://addons/world_runtime/generation_screen.gd").new();add_child(loading)
	loading.panel.preferences_path="";loading.cancel_button.disabled=true
	show_screen(0)
func show_screen(index:int)->void:
	current=clampi(index,0,3)
	if browser==null:return
	browser.visible=current<2;loading.visible=current>=2
	if current<2:browser.world_tabs.current_tab=current
	elif current==2:
		loading.panel.reset();loading.update_stage("Placing buildings and interiors",4,10,{"work":"Preview data · no generation job"})
	else:
		loading.panel.reset();loading.panel.show_progress("Loading your world","Preview · loading nearby terrain and collision",68)
func set_mock_time(_seconds:float)->void:pass
