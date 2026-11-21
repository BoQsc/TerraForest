# SPDX-License-Identifier: 0BSD
@tool
extends EditorExportPlugin

var active:=false

func _get_name()->String:
 return "TerraForestWaterQualification"

func _export_begin(_features:PackedStringArray,_is_debug:bool,path:String,_flags:int)->void:
 var requested:=OS.get_environment("TERRAFOREST_WATER_QUALIFICATION_PACK").replace("\\","/")
 active=not requested.is_empty() and ProjectSettings.globalize_path(path).simplify_path()==requested.simplify_path()
 if active:
  add_file("res://qualification/water_player_world.gd",FileAccess.get_file_as_bytes(OS.get_environment("TERRAFOREST_WATER_QUALIFICATION_DRIVER")),false)

func _export_file(path:String,_type:String,_features:PackedStringArray)->void:
 if not active or path!="res://demo/worlds.tscn":return
 # Only the initial scene is replaced. The driver instantiates the same packed
 # world scene, terrain, actors, water and normal input handlers as the game.
 var scene:="[gd_scene load_steps=2 format=3]\n[ext_resource type=\"Script\" path=\"res://qualification/entry.gd\" id=\"1\"]\n[node name=\"Qualification\" type=\"Node\"]\nscript = ExtResource(\"1\")\n"
 add_file("res://qualification/entry.gd",FileAccess.get_file_as_bytes("res://tools/water_release_entry.gd"),false)
 add_file("res://qualification/entry.tscn",scene.to_utf8_buffer(),true)
 print("WATER_RELEASE_MAIN_SCENE ",path)

func _export_end()->void:
 active=false
