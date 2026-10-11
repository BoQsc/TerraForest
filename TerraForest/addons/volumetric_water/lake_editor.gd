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
 menu.label(self,"Carve creates a basin at your aim. Removing water keeps the carved terrain. These are static lakes; opening a basin beyond its bounds prevents it from filling.")
 menu.button(self,"Carve lake at aim",func():
  if menu.developer:menu.run_command(KEY_L))
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
