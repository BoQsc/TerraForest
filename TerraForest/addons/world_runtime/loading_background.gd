# SPDX-License-Identifier: 0BSD
extends Control
# One static photograph and dim overlay, shared by generation and gameplay load.
var picture:TextureRect
var shade:ColorRect
func _ready()->void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
 var fill:=ColorRect.new();fill.color=Color("101b1c");fill.mouse_filter=Control.MOUSE_FILTER_IGNORE;fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(fill)
 picture=TextureRect.new();picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
 picture.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
 picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(picture)
 shade=ColorRect.new();shade.name="BackgroundDim";shade.color=Color(0.01,0.02,0.03,0.5);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
 shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
