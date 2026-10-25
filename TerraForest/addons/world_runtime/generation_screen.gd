# SPDX-License-Identifier: 0BSD
extends CanvasLayer
signal cancel_requested
const Meter=preload("res://addons/world_runtime/progress_meter.gd")
var detail:Label
var title:Label
var background:Control
var picture:TextureRect
var panel:PanelContainer
var diagnostics:Control
var cancel_path:=""
var cancel_button:Button
var cancellation_requested:=false
func _ready()->void:
 preload("res://addons/world_runtime/mouse_ownership.gd").set_mode(self,Input.MOUSE_MODE_VISIBLE)
 layer=120
 background=preload("res://addons/world_runtime/loading_background.gd").new();add_child(background)
 picture=background.picture
 diagnostics=preload("res://addons/world_runtime/loading_details.gd").new();add_child(diagnostics)
 panel=preload("res://addons/world_runtime/loading_panel.gd").new();add_child(panel)
 detail=panel.detail;title=panel.title;cancel_button=panel.action
 panel.reset(preload("res://addons/world_runtime/loading_timer.gd").requested_start())
 panel.show_progress("Generating your world","Planning terrain and locations…",0)
 cancel_button.text="Cancel generation";cancel_button.disabled=cancel_path.is_empty()
 cancel_button.pressed.connect(func():
  var request:=FileAccess.open(cancel_path,FileAccess.WRITE)
  if request==null:detail.text="Could not request cancellation.";return
  request.store_string("cancel");request.close();panel.stop_timer("cancelling");diagnostics.observe("Cancelling generation…",{"cancel_file":cancel_path});cancellation_requested=true;cancel_button.disabled=true;detail.text="Cancelling generation…";cancel_requested.emit())
func update_stage(stage:String,completed:int,total:int,details:Dictionary={})->void:
 if detail==null or cancellation_requested:return
 panel.show_progress("Generating your world",str(details.get("activity",stage))+("  ·  %d / %d"%[completed,total] if total>0 and not details.has("activity") else ""),Meter.generation(stage,completed,total,details))
 panel.show_work(str(details.get("work","")))
 diagnostics.observe(str(details.get("activity",stage)),{"stage":stage,"completed":completed,"total":total,"details":details,"timing":panel.timing_snapshot()})
func update_status(state:String,stage:String,observation:Dictionary,coordinator:Dictionary={})->void:
 if detail==null or cancellation_requested:return
 panel.show_progress("Loading your world" if state=="ready" else "Generating your world",stage,Meter.coordinator(state,observation))
 panel.show_work(str(observation.get("details",{}).get("work","")))
 if state in ["failed","cancelled"]:panel.stop_timer(state)
 diagnostics.observe(stage,{"coordinator":coordinator,"observation":observation,"timing":panel.timing_snapshot()})
func use_photograph(path:String)->void:
 var image:=Image.load_from_file(path)
 if image!=null:picture.texture=ImageTexture.create_from_image(image)
