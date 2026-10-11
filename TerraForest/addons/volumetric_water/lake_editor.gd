# SPDX-License-Identifier: 0BSD
extends VBoxContainer
# Event-driven UI over at most sixteen definitions; no simulation or per-frame work.
var game: Node
var rows: VBoxContainer
var refresh_queued:=false
func _ready() -> void:
 add_theme_constant_override("separation",12)
 var menu=game.session_menu
 menu.label(self,"Water / lakes").add_theme_font_size_override("font_size",22)
 menu.label(self,"Water follows edited terrain. Buckets scoop / pour 1 L, including new locations. Development brushes add or remove water directly. Saved regions reuse prepared terrain occupancy.")
 menu.button(self,"Carve lake at aim",func():
  if menu.developer:menu.run_command(KEY_L))
 menu.button(self,"Give empty bucket (development)",func():
  if not menu.developer:return
  var inventory=game.player_hud.inventory
  var result:Dictionary=inventory.grant(401,1,inventory.snapshot().revision)
  if result.ok:game.player_hud.refresh();game.terrain.changed_since_save=true
  menu.message.text="Bucket added to inventory" if result.ok else "Inventory full")
 menu.button(self,"Add water at aim (1,000 L)",water_brush.bind(false))
 menu.button(self,"Remove water at aim (2 m brush)",water_brush.bind(true))
 rows=VBoxContainer.new();rows.add_theme_constant_override("separation",12);add_child(rows)
 game.lakes.catalog_changed.connect(schedule_refresh)
 rebuild()
func schedule_refresh() -> void:
 if refresh_queued:return
 refresh_queued=true;rebuild.call_deferred()
func rebuild() -> void:
 refresh_queued=false
 if rows==null:return
 for child in rows.get_children():rows.remove_child(child);child.queue_free()
 var entries: Array[Dictionary]=game.lakes.descriptions()
 if entries.is_empty():game.session_menu.label(rows,"No lakes in this world.")
 for entry in entries:
  var row=HBoxContainer.new();row.add_theme_constant_override("separation",12);rows.add_child(row)
  var text="Lake %d | %s | water elevation %.1f m"%[entry.id,entry.state,entry.level]
  if not entry.reason.is_empty():text+="\n"+entry.reason
  var title=game.session_menu.label(row,text);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.custom_minimum_size.x=420
  if entry.state=="Failed":game.session_menu.button(row,"Retry bake",retry.bind(entry.id))
  game.session_menu.button(row,"Remove water",remove.bind(entry.id))
func retry(id: int) -> void:
 if not game.session_menu.developer:return
 game.session_menu.message.text="Lake bake queued" if game.lakes.retry_lake(id) else "Wait for terrain edits to finish, then retry."
func remove(id: int) -> void:
 if not game.session_menu.developer:return
 game.lakes.remove_lake(id)
 game.session_menu.message.text="Water removed; terrain unchanged. Save world to keep this change."

func water_brush(remove:bool) -> void:
 if not game.session_menu.developer:return
 var start:Vector3=game.camera.global_position
 var end:Vector3=start-game.camera.global_basis.z*5.0
 var hit:Dictionary=game.structures.blocks.raycast_scene(start,end,0xFFFFFFFF,[game.player.get_rid()])
 if not hit.is_empty():end=hit.position+hit.normal*0.05
 game.lakes.dev_brush(end,remove)
 game.session_menu.message.text="Water removal applied" if remove else "Water addition queued at aim"
