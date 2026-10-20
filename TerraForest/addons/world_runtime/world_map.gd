# SPDX-License-Identifier: 0BSD
extends CanvasLayer
const Survey=preload("res://addons/world_runtime/survey_cache.gd")
const Layout=preload("res://addons/volumetric_terrain/generated_layout.gd")
var game:Node
var opened:=false
var panel:PanelContainer
var view:Control
var status:Label
var position_label:Label
var destination_list:VBoxContainer
var texture:ImageTexture
var key:=""
var worker:Thread
var job_key:=""
var last_profile:Dictionary={}
var builds:=0
var roads:Array[Dictionary]=[]
var places:Array[Dictionary]=[]
var timer:Timer
var updates:Node
func _ready()->void:
 layer=50
 updates=preload("res://addons/world_runtime/survey_updates.gd").new();updates.atlas=self;add_child(updates)
 panel=PanelContainer.new();panel.position=Vector2(100,50);panel.size=Vector2(1720,980);add_child(panel)
 var style:=StyleBoxFlat.new();style.bg_color=Color("12262b")
 for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(side,22)
 panel.add_theme_stylebox_override("panel",style)
 var root:=VBoxContainer.new();root.add_theme_constant_override("separation",12);panel.add_child(root)
 var header:=HBoxContainer.new();root.add_child(header)
 var title:=Label.new();title.text="WORLD MAP / REGIONAL SURVEY";title.add_theme_font_size_override("font_size",26);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
 add_button(header,"Close  ·  M / Esc",func():set_open(false))
 var columns:=HBoxContainer.new();columns.add_theme_constant_override("separation",20);columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;root.add_child(columns)
 view=preload("res://addons/world_runtime/world_map_view.gd").new();view.atlas=self;view.custom_minimum_size=Vector2(1100,790);view.size_flags_horizontal=Control.SIZE_EXPAND_FILL;view.size_flags_vertical=Control.SIZE_EXPAND_FILL;columns.add_child(view)
 var sidebar:=VBoxContainer.new();sidebar.custom_minimum_size.x=340;sidebar.add_theme_constant_override("separation",12);columns.add_child(sidebar)
 position_label=add_label(sidebar,"")
 var buttons:=HBoxContainer.new();sidebar.add_child(buttons)
 add_button(buttons,"Find me",view.follow_player);add_button(buttons,"Whole world",view.overview)
 var zoom_row:=HBoxContainer.new();sidebar.add_child(zoom_row)
 add_button(zoom_row,"− Zoom",func():view.set_zoom(view.zoom/1.5,view.size*0.5));add_button(zoom_row,"+ Zoom",func():view.set_zoom(view.zoom*1.5,view.size*0.5))
 add_label(sidebar,"Drag to pan · Wheel to zoom\nNorth is up · Mint arrow: you\nGold: roads · Blue: lakes")
 add_label(sidebar,"PUBLIC DESTINATIONS").add_theme_font_size_override("font_size",18)
 var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;sidebar.add_child(scroll)
 destination_list=VBoxContainer.new();destination_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(destination_list)
 add_button(sidebar,"Stop tracking",func():game.destination_guide.clear();view.queue_redraw())
 status=add_label(root,"Survey preparing…")
 timer=Timer.new();timer.wait_time=0.2;timer.timeout.connect(update_position);add_child(timer)
 panel.hide();set_process(false)
func add_label(parent:Node,text:String)->Label:
 var label:=Label.new();label.text=text;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(label);return label
func add_button(parent:Node,text:String,action:Callable)->Button:
 var b:=Button.new();b.text=text;b.custom_minimum_size.y=42;b.focus_mode=Control.FOCUS_NONE;b.pressed.connect(action);parent.add_child(b);return b
func set_open(value:bool)->void:
 if value and (game.loading_active or game.shutdown_requested or not game.terrain.world_ready or not game.app_focused or game.benchmark_enabled):return
 if value:
  game.session_menu.set_open(false);game.storage.close();game.player_hud.set_open(false)
  game.session_menu.developer_hud.mouse_access=false
 opened=value;panel.visible=value;view.dragging=false;updates.set_process(value)
 game.player_hud.inventory_open=value;game.player_hud.enabled=not value and not game.world_vehicle.driving
 game._clear_motion();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
 game.session_menu.refresh();game.session_menu.sync_panels()
 if value:
  refresh_world();view.follow_player();timer.start();update_position()
 else:timer.stop()
func refresh_world()->void:
 var seed_value:int=game.terrain.backend.world_seed;var generator:int=game.terrain.backend.world_generator
 var next_key:="%d/%d/%d"%[seed_value,generator,game.terrain.epoch]
 if next_key!=key:
  key=next_key;texture=null;places.clear();updates.reset()
  var layout:Dictionary=Layout.describe(seed_value,generator)
  if not layout.is_empty():
   var names:=["Central settlement","West settlement","East settlement","North neighborhood","South settlement"]
   for site:Dictionary in layout.sites:places.append({"title":names[site.id],"position":site.position})
  # Public basin shores only. Underground/secret descriptors are never enumerated.
  var core=ClassDB.instantiate("TerrainCore");core.execute(Survey.Codec.command(6,[seed_value,generator]))
  var data:PackedByteArray=core.execute(Survey.Codec.command(27))
  if Survey.Codec.reply_ok(data) and data.size()==192:
   for i in 4:
    var at:=16+i*44
    places.append({"title":"Large lake" if generator>=12 and i==0 else "Pond %d"%(i+1),"position":Vector3(data.decode_float(at+32)+(72 if generator>=12 and i==0 else 27),data.decode_float(at+28),data.decode_float(at+40))})
  for child in destination_list.get_children():child.queue_free()
  for place:Dictionary in places:add_button(destination_list,place.title,func():game.destination_guide.track(place);view.queue_redraw())
 roads.clear()
 var layout:Dictionary=Layout.describe(seed_value,generator)
 if not layout.is_empty():
  for road:Dictionary in layout.roads:roads.append({"a":layout.sites[road.from].position,"b":layout.sites[road.to].position,"width":road.half_width*2})
 for street:Dictionary in game.road_palette.prepared_streets:
  if street.ends.size()==2:roads.append({"a":street.ends[0],"b":street.ends[1],"width":street.width})
 if texture==null and worker==null:
  job_key=key;worker=Thread.new();builds+=1
  if worker.start(Survey.build.bind(seed_value,generator))==OK:set_process(true)
  else:worker=null;status.text="Survey unavailable. Close and reopen to retry."
 else:status.text=updates.description()
func _process(_delta:float)->void:
 if worker==null:set_process(false);return
 if worker.is_alive():return
 var result:Dictionary=worker.wait_to_finish();worker=null;set_process(false)
 if job_key!=key:
  if opened:refresh_world()
  return
 if not result.get("ok",false):status.text="Survey unavailable. Close and reopen to retry.";return
 last_profile=result.duplicate();last_profile.erase("pixels")
 updates.image=Image.create_from_data(Survey.SIZE,Survey.SIZE,false,Image.FORMAT_RGBA8,result.pixels)
 texture=ImageTexture.create_from_image(updates.image)
 status.text=updates.description()
 view.queue_redraw()
func update_position()->void:
 if not opened:return
 if game.loading_active or game.shutdown_requested:set_open(false);return
 var at:Vector3=game.player.global_position
 position_label.text="YOUR POSITION\nE %.0f m   S %.0f m\nElevation %.0f m"%[at.x,at.z,at.y]
 view.queue_redraw()
func _exit_tree()->void:
 if worker!=null:worker.wait_to_finish();worker=null
