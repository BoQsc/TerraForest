# SPDX-License-Identifier: 0BSD
extends Node3D
const LIBRARY="res://addons/world_runtime/assets/landform_library.json"
var library:Dictionary
var worker:Thread
var native:RefCounted=ClassDB.instantiate("NativeLandformLab")
var camera:=Camera3D.new()
var terrain_view:=MeshInstance3D.new()
var water_view:=MeshInstance3D.new()
var selector:=OptionButton.new()
var seed_field:=SpinBox.new()
var layer:=OptionButton.new()
var map_view:=TextureRect.new()
var details:=Label.new()
var intent:=Label.new()
var result:Dictionary={}
var angle:=-0.65
var elevation:=0.85
var distance:=850.0
var target:=Vector3(384,45,384)
var ready_for_review:=false
func _ready()->void:
 add_child(camera);camera.far=4000;camera.current=true
 add_child(terrain_view);add_child(water_view)
 var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.vertex_color_use_as_albedo=true;material.cull_mode=BaseMaterial3D.CULL_DISABLED
 terrain_view.material_override=material;water_view.material_override=material
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("16242a");add_child(environment)
 var canvas:=CanvasLayer.new();add_child(canvas)
 var panel:=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);canvas.add_child(panel)
 var column:=VBoxContainer.new();panel.add_child(column)
 var title:=Label.new();title.text="TerraForest · Generation laboratory";title.add_theme_font_size_override("font_size",23);column.add_child(title)
 var row:=HBoxContainer.new();column.add_child(row);row.add_child(selector);row.add_child(seed_field);row.add_child(layer)
 seed_field.min_value=0;seed_field.max_value=2147483647;seed_field.value=1703;seed_field.custom_minimum_size.x=140
 layer.add_item("3D terrain");layer.add_item("Terrain map");layer.add_item("Vegetation coverage")
 var build_button:=Button.new();build_button.text="Reload modules / build";row.add_child(build_button);build_button.pressed.connect(reload_library)
 column.add_child(intent);intent.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 column.add_child(details);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 var help:=Label.new();help.text="Right-drag to orbit · wheel to zoom · JSON modules can be reused, transformed and edited.\nTerrain study: vegetation colors show planned coverage; these are not populated gameplay worlds.";column.add_child(help)
 canvas.add_child(map_view);map_view.position=Vector2(190,205);map_view.size=Vector2(590,590);map_view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;map_view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;map_view.mouse_filter=Control.MOUSE_FILTER_IGNORE
 selector.item_selected.connect(func(_i):rebuild());layer.item_selected.connect(func(_i):show_layer())
 reload_library();update_camera()
func reload_library()->void:
 if worker!=null:return
 var parsed=JSON.parse_string(FileAccess.get_file_as_string(LIBRARY))
 if not parsed is Dictionary:details.text="The module library could not be read.";return
 library=parsed;var selected:=maxi(0,selector.selected);selector.clear()
 for case:Dictionary in library.cases:selector.add_item(case.title)
 selector.select(mini(selected,selector.item_count-1));rebuild()
func choose(index:int)->void:
 selector.select(index);rebuild()
func build_case(document:Dictionary,id:String,seed_value:int)->Dictionary:
 var compiled:Dictionary=native.compile(document,id,seed_value)
 if not compiled.get("ok",false):return compiled
 var sampled:Dictionary=native.raster(compiled.program,257,true)
 sampled["compile_ms"]=compiled.compile_ms;return sampled
func rebuild()->void:
 if worker!=null:return
 ready_for_review=false;details.text="Compiling reusable modules and sampling native geometry…";selector.disabled=true
 var case:Dictionary=library.cases[selector.selected];intent.text=case.intent
 worker=Thread.new();worker.start(build_case.bind(library,case.id,int(seed_field.value)))
func _process(_delta:float)->void:
 if worker==null or worker.is_alive():return
 result=worker.wait_to_finish();worker=null;selector.disabled=false
 if not result.get("ok",false):details.text="Rejected: "+str(result.get("reason","unknown error"));return
 terrain_view.mesh=result.terrain_mesh;water_view.mesh=result.get("water_mesh")
 target=Vector3(result.extent*.5,50,result.extent*.5);update_camera()
 var m:Dictionary=result.metrics
 details.text="%.2f ms compile + %.2f ms sample/mesh · %.1f KiB program · %d lake component(s) · %.2f km shoreline\nPotential coverage: woodland %.0f%% · grass %.0f%% · gentle dry ground %.0f%%. Counts do not establish visual quality."%[result.compile_ms,m.total_ms,m.program_bytes/1024.0,m.lake_components,m.shoreline_m/1000.0,m.woodland_fraction*100,m.grass_fraction*100,m.buildable_fraction*100]
 ready_for_review=true;show_layer();print("GENERATION_LAB_READY ",library.cases[selector.selected].id)
func show_layer()->void:
 map_view.visible=layer.selected>0;terrain_view.visible=layer.selected==0;water_view.visible=layer.selected==0
 if map_view.visible and result.get("ok",false):
  var pixels:PackedByteArray=result.ecology_pixels if layer.selected==2 else result.pixels
  map_view.texture=ImageTexture.create_from_image(Image.create_from_data(int(result["size"]),int(result["size"]),false,Image.FORMAT_RGBA8,pixels))
func update_camera()->void:
 camera.position=target+Vector3(cos(angle)*cos(elevation),sin(elevation),sin(angle)*cos(elevation))*distance;camera.look_at(target)
func _unhandled_input(event:InputEvent)->void:
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):angle-=event.relative.x*.006;elevation=clampf(elevation+event.relative.y*.004,.12,1.5);update_camera()
 if event is InputEventMouseButton and event.pressed:
  if event.button_index==MOUSE_BUTTON_WHEEL_UP:distance=maxf(180,distance*.9);update_camera()
  if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:distance=minf(1900,distance/ .9);update_camera()
func _exit_tree()->void:
 if worker!=null:worker.wait_to_finish();worker=null
