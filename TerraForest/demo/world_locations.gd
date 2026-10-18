# SPDX-License-Identifier: 0BSD
extends VBoxContainer
const Layout=preload("res://addons/volumetric_terrain/generated_layout.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var game:Node
var destinations:Array[Dictionary]=[]
var layout_key:=""
func _ready()->void:
 add_theme_constant_override("separation",12)
 visibility_changed.connect(refresh)
func refresh()->void:
 if not is_visible_in_tree():return
 for child in get_children():remove_child(child);child.queue_free()
 var menu=game.session_menu
 menu.label(self,"World destinations").add_theme_font_size_override("font_size",24)
 if game.loading_active or not game.terrain.world_ready:
  menu.label(self,"World loading. Reopen this page when ready.");return
 var key:="%d/%d"%[game.terrain.backend.world_seed,game.terrain.backend.world_generator]
 if key!=layout_key:
  destinations=describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator);layout_key=key
 menu.label(self,"Follow the regional roads from the central settlement to the western, eastern, northern and southern districts. Explore the eastern mine or visit the lake shores.")
 menu.label(self,"Track a destination for its direction and distance while walking or driving. The guide points directly toward the location; use roads and entrances to get there. Development mode enables travel buttons.")
 if not game.destination_guide.destination.is_empty():
  menu.button(self,"Stop tracking: "+str(game.destination_guide.destination.title),func():game.destination_guide.clear();refresh())
 if destinations.is_empty():menu.label(self,"This generator has no regional destination directory.")
 for destination:Dictionary in destinations:
  var row:=HBoxContainer.new();add_child(row)
  var distance:=Vector2(game.player.position.x-destination.position.x,game.player.position.z-destination.position.z).length()
  var caption=menu.label(row,"%s  ·  %.0f m away\n%s"%[destination.title,distance,destination.detail]);caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  menu.button(row,"Track",track.bind(destination))
  if menu.developer:
   var go=menu.button(row,"Travel here",travel.bind(destination.position));go.disabled=game.world_vehicle.driving
func track(destination:Dictionary)->void:
 if game.destination_guide.track(destination):game.session_menu.set_open(false)
func travel(position:Vector3)->void:
 if not game.session_menu.developer:return
 if game.loading_active or game.shutdown_requested or game.world_vehicle.driving or game.terrain.pending_edit or game.site_preparation.status=="running" or game.site_survey.busy or not game._foundation_placement.is_empty() or not game.road_authoring.phase.is_empty():
  game.session_menu.message.text="Finish the current action and exit the vehicle before travelling.";return
 game.session_menu.set_open(false);game._cancel_edit_input();game.teleport(position)
static func describe(seed_value:int,generator:int)->Array[Dictionary]:
 var result:Array[Dictionary]=[]
 var layout:Dictionary=Layout.describe(seed_value,generator)
 if layout.is_empty():return result
 var names:=["Central settlement site","West settlement site","East settlement site","North settlement site","South settlement site"]
 for site:Dictionary in layout.sites:
  result.append({"title":names[site.id],"position":site.position,"detail":"Connected by the regional road network."})
 for mine:Dictionary in layout.underground:
  result.append({"title":"Eastern mine entrance","position":mine.entrance+Vector3(10,0,0),"detail":"Mine workings and chambers belonging to the eastern location."})
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,generator]))
 var lakes:PackedByteArray=core.execute(Codec.command(27))
 if Codec.reply_ok(lakes) and lakes.size()==192:
  for i in 4:
   var at:=16+i*44
   var shore:=Vector3(lakes.decode_float(at+32),lakes.decode_float(at+28),lakes.decode_float(at+40))+Vector3(72 if generator>=12 and i==0 else 27,0,0)
   result.append({"title":"Large lake shore" if generator>=12 and i==0 else "Pond %d shore"%(i+1),"position":shore,"detail":"Dry-ground arrival beside the generated basin."})
 return result
