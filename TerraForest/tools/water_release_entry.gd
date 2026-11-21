# SPDX-License-Identifier: 0BSD
extends Node

func _ready()->void:
 start_check.call_deferred()

func start_check()->void:
 var tree:=get_tree()
 if not OS.get_cmdline_user_args().has("--water-qualification-driver=res://qualification/water_player_world.gd"):
  tree.quit(2)
  return
 var driver:Script=load("res://qualification/water_player_world.gd")
 if driver==null or not driver.can_instantiate():
  tree.quit(2)
  return
 tree.set_script(driver)
 tree.call_deferred("run")
 queue_free()
