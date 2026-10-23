# SPDX-License-Identifier: 0BSD
extends CanvasLayer
signal cancel_requested
const Meter=preload("res://addons/world_runtime/progress_meter.gd")
var detail:Label
var title:Label
var picture:TextureRect
var panel:PanelContainer
var cancel_path:=""
var cancel_button:Button
var cancellation_requested:=false
func _ready()->void:
 layer=120
 var fill:=ColorRect.new();fill.color=Color("101b1c");fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(fill)
 picture=TextureRect.new();picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;add_child(picture)
 panel=preload("res://addons/world_runtime/loading_panel.gd").new();add_child(panel)
 detail=panel.detail;title=panel.title;cancel_button=panel.action
 panel.show_progress("Generating your world","Planning terrain and locations…",0)
 cancel_button.text="Cancel generation";cancel_button.disabled=cancel_path.is_empty()
 cancel_button.pressed.connect(func():
  var request:=FileAccess.open(cancel_path,FileAccess.WRITE)
  if request==null:detail.text="Could not request cancellation.";return
  request.store_string("cancel");request.close();cancellation_requested=true;cancel_button.disabled=true;detail.text="Cancelling generation…";cancel_requested.emit())
func _process(_delta:float)->void:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
func update_stage(stage:String,completed:int,total:int,details:Dictionary={})->void:
 if detail==null or cancellation_requested:return
 panel.show_progress("Generating your world",str(details.get("activity",stage))+("  ·  %d / %d"%[completed,total] if total>0 and not details.has("activity") else ""),Meter.generation(stage,completed,total,details))
 panel.show_work(str(details.get("work","")))
func update_status(state:String,stage:String,observation:Dictionary)->void:
 if detail==null or cancellation_requested:return
 panel.show_progress("Loading your world" if state=="ready" else "Generating your world",stage,Meter.coordinator(state,observation))
 panel.show_work(str(observation.get("details",{}).get("work","")))
func use_photograph(path:String)->void:
 var image:=Image.load_from_file(path)
 if image!=null:picture.texture=ImageTexture.create_from_image(image)
