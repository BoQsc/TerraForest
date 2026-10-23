# SPDX-License-Identifier: 0BSD
extends CanvasLayer
# Presentation only. All heavy work remains in existing native-backed services.
var detail:Label
var title:Label
var picture:TextureRect
var cancel_path:=""
var cancel_button:Button
func _ready()->void:
 layer=120
 var fill:=ColorRect.new();fill.color=Color("101b1c");fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(fill)
 picture=TextureRect.new();picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;add_child(picture)
 var panel:=PanelContainer.new();panel.position=Vector2(80,790);panel.size=Vector2(1180,220);add_child(panel)
 var margin:=MarginContainer.new()
 for side:String in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,24)
 panel.add_child(margin)
 var box:=VBoxContainer.new();box.add_theme_constant_override("separation",14);margin.add_child(box)
 title=Label.new();title.text="Generating your world";title.add_theme_font_size_override("font_size",32);box.add_child(title)
 detail=Label.new();detail.add_theme_font_size_override("font_size",22);detail.text="Planning terrain and locations…";box.add_child(detail)
 var hint:=Label.new();hint.text="Generate  →  Load  →  Play";hint.add_theme_font_size_override("font_size",18);box.add_child(hint)
 cancel_button=Button.new();cancel_button.text="Cancel generation";cancel_button.position=Vector2(1510,940);cancel_button.size=Vector2(310,64);cancel_button.disabled=cancel_path.is_empty();add_child(cancel_button)
 cancel_button.pressed.connect(func():
  var request:=FileAccess.open(cancel_path,FileAccess.WRITE)
  if request==null:detail.text="Could not request cancellation.";return
  request.store_string("cancel");request.close();cancel_button.disabled=true;detail.text="Cancelling generation…")
func _process(_delta:float)->void:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
func update_stage(stage:String,completed:int,total:int)->void:
 if detail==null:return
 detail.text=stage+("  ·  %d / %d"%[completed,total] if total>0 else "")
func use_photograph(path:String)->void:
 var image:=Image.load_from_file(path)
 if image!=null:picture.texture=ImageTexture.create_from_image(image)
