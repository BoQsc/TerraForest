# SPDX-License-Identifier: 0BSD
extends RefCounted
## Temporary, independent pistol switches. No movement, aim or damage owner here.
const OPTIONS={
	"bobbing":"Walking bob",
	"sway":"Turning and movement sway",
	"crosshair":"Dynamic crosshair and confirmed-hit marker",
	"reaction":"Physical hit reactions",
	"animation":"Zombie hit animations",
	"blood":"Blood splash",
	"dismemberment":"More frequent limb dismemberment"
}
var values:Dictionary={}
var controls:Dictionary={}
var settings_path:String=ProjectSettings.get_setting("terraforest/pistol_trial_settings_path","user://pistol_trial.cfg")
var phase:=0.0
var bob:=Vector3.ZERO
var sway:=Vector3.ZERO
var bank:=0.0
func _init()->void:
	for key:String in OPTIONS:values[key]=true
func load_settings()->void:
	if settings_path.is_empty() or ProjectSettings.get_setting("terraforest/offscreen_session",false):return
	var config:=ConfigFile.new()
	if config.load(settings_path)!=OK:return
	for key:String in OPTIONS:values[key]=config.get_value("pistol",key,true)==true
func set_option(key:String,value:bool,persist:=true)->void:
	if not OPTIONS.has(key):return
	values[key]=value;reset_motion()
	if persist and not settings_path.is_empty() and not ProjectSettings.get_setting("terraforest/offscreen_session",false):
		var config:=ConfigFile.new()
		for option:String in OPTIONS:config.set_value("pistol",option,values[option])
		config.save(settings_path)
	if controls.has(key):
		var toggle:CheckButton=controls[key].get_ref()
		if toggle!=null:toggle.set_pressed_no_signal(value)
func add_controls(menu:CanvasLayer,parent:Node)->void:
	menu.label(parent,"Pistol feel · temporary trial").add_theme_font_size_override("font_size",22)
	menu.label(parent,"Changes apply immediately. Each effect can be switched off independently. Aim and bullet accuracy stay unchanged.")
	for key:String in OPTIONS:
		var toggle:=CheckButton.new();toggle.name="Pistol_"+key;toggle.text=OPTIONS[key];toggle.button_pressed=values[key]
		toggle.toggled.connect(func(value:bool):set_option(key,value));parent.add_child(toggle)
		controls[key]=weakref(toggle)
		if key=="dismemberment":toggle.tooltip_text="Adds a 20% sever chance on accepted pistol hits to arms and legs. Head and torso damage remain unchanged. Off restores normal limb durability."
		if key=="blood":toggle.tooltip_text="Uses the existing bounded impact-effect pool. The global impact-effects switch also applies."
	menu.button(parent,"Disable all pistol trial effects",func():
		for key:String in OPTIONS:set_option(key,false))
	menu.button(parent,"Restore pistol trial defaults",func():
		for key:String in OPTIONS:set_option(key,true))
func reset_motion()->void:
	phase=0;bob=Vector3.ZERO;sway=Vector3.ZERO;bank=0
func motion(delta:float,velocity:Vector3,grounded:bool,turn:float,aiming:bool)->Transform3D:
	var dt:=clampf(delta,0,.05)
	var weight:=.15 if aiming else 1.0
	var speed:=Vector2(velocity.x,velocity.z).length()
	var walking:=grounded and speed>.1
	if walking:phase=fmod(phase+dt*clampf(speed*2.5,0,16),TAU)
	var target:=Vector3(sin(phase)*.007,cos(phase*2)*.005,0)*minf(speed/4,1)*weight if walking and values.bobbing else Vector3.ZERO
	bob=bob.lerp(target,1-exp(-14*dt)) if values.bobbing else Vector3.ZERO
	sway=sway.lerp(Vector3(clampf(-velocity.x*.0015,-.008,.008),0,clampf(velocity.z*.001,-.006,.006))*weight,1-exp(-10*dt)) if values.sway else Vector3.ZERO
	bank=lerpf(bank,clampf(-turn*.012,-.025,.025)*weight,1-exp(-14*dt)) if values.sway else 0.0
	return Transform3D(Basis.from_euler(Vector3(0,bank*.4,bank)),bob+sway)
func extra_sever(part:String,roll:float)->bool:
	return values.dismemberment and part not in ["head","torso"] and roll>=0 and roll<.2
