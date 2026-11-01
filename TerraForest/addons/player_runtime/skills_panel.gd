# SPDX-License-Identifier: 0BSD
extends VBoxContainer

const Rules=preload("res://addons/player_runtime/progression_rules.gd")
var hud:Node
var summary:Label
var progress:ProgressBar
var buttons:Array[Button]=[]
var shown_revision:=-1

func _ready()->void:
	add_theme_constant_override("separation",16)
	var title:=Label.new();title.text="SKILLS";title.add_theme_font_size_override("font_size",26);add_child(title)
	summary=Label.new();summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(summary)
	progress=ProgressBar.new();progress.custom_minimum_size.y=16;progress.show_percentage=false;add_child(progress)
	var background:=StyleBoxFlat.new();background.bg_color=Color("20352f");background.set_corner_radius_all(4)
	var fill:=StyleBoxFlat.new();fill.bg_color=Color("75c8a0");fill.set_corner_radius_all(4)
	progress.add_theme_stylebox_override("background",background);progress.add_theme_stylebox_override("fill",fill)
	var help:=Label.new();help.text="Learn by harvesting, mining, fighting and crafting. Each level grants one skill point."
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(help)
	for skill:Dictionary in Rules.SKILLS:
		var button:=Button.new();button.custom_minimum_size=Vector2(370,62);button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(spend.bind(skill.id));add_child(button);buttons.append(button)
		var detail:=Label.new();detail.text=skill.detail;detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(detail)
	refresh()

func refresh()->void:
	if summary==null:return
	var state:Dictionary=hud.progression.snapshot()
	if shown_revision==state.revision:return
	shown_revision=state.revision
	summary.text="Level %d · %d available skill points\n%d XP%s"%[state.level,state.points,state.xp," · maximum level" if state.level==state.maximum_level else " / %d for next level"%state.next_level]
	progress.max_value=maxi(1,state.next_level-state.level_start)
	progress.value=progress.max_value if state.level==state.maximum_level else state.xp-state.level_start
	for index in buttons.size():
		var skill:Dictionary=Rules.SKILLS[index];var rank:int=state.skills[skill.id]
		buttons[index].text="%s · %d / %d\n%s"%[skill.name,rank,skill.maximum,"Maximum rank" if rank==skill.maximum else "Improve · 1 point"]
		buttons[index].disabled=state.points<1 or rank>=skill.maximum

func spend(skill:int)->void:
	if not hud.inventory_open or not visible:return
	var result:Dictionary=hud.progression.spend(skill,shown_revision)
	if result.ok:hud.progression_changed.emit()
	refresh()
