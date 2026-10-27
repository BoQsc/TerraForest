# SPDX-License-Identifier: 0BSD
extends Control
# Bounded vector overlays over one cached texture. UI only; no world queries.
var atlas:Node
var center:=Vector2(1000,1000)
var zoom:=1.0
var dragging:=false
var teleport_click:=false
var drag_distance:=0.0
var label_boxes:Array[Rect2]=[]
func _ready()->void:
 clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP
func pixels_per_metre()->float:return minf(size.x,size.y)/2000.0*zoom
func world_to_map(point:Vector3)->Vector2:return size*0.5+(Vector2(point.x,point.z)-center)*pixels_per_metre()
func map_to_world(point:Vector2)->Vector2:return center+(point-size*0.5)/pixels_per_metre()
func set_zoom(value:float,anchor:Vector2)->void:
 var at:=map_to_world(anchor);zoom=clampf(value,1,12)
 center+=(at-map_to_world(anchor));bound_center();queue_redraw()
func bound_center()->void:center=center.clamp(Vector2.ZERO,Vector2.ONE*2000)
func overview()->void:center=Vector2(1000,1000);zoom=1;queue_redraw()
func follow_player()->void:
 var at:Vector3=atlas.game.player.global_position;center=Vector2(at.x,at.z);zoom=4;bound_center();queue_redraw()
func marker_at(point:Vector2)->int:
 var identity:=0;var nearest:=14.0
 for marker:Dictionary in atlas.game.map_markers.markers:
  var distance:=world_to_map(Vector3(marker.point.x,0,marker.point.y)).distance_to(point)
  if distance<nearest:identity=marker.id;nearest=distance
 return identity
func _gui_input(event:InputEvent)->void:
 if event is InputEventMouseButton:
  if event.button_index==MOUSE_BUTTON_LEFT:
   if event.pressed:dragging=true;drag_distance=0;teleport_click=event.ctrl_pressed
   else:
    var clicked:=dragging and drag_distance<5
    dragging=false
    if clicked:
     if teleport_click:
      if event.ctrl_pressed and Rect2(Vector2.ZERO,size).has_point(event.position):atlas.teleport_to(map_to_world(event.position))
     else:
      var identity:=marker_at(event.position)
      if identity!=0:atlas.game.destination_guide.track(atlas.game.map_markers.describe(identity));queue_redraw()
      for place:Dictionary in atlas.places+(atlas.deposits if atlas.show_deposits else []):
       if identity==0 and world_to_map(place.position).distance_to(event.position)<14:atlas.game.destination_guide.track(place);queue_redraw();break
    teleport_click=false
   accept_event()
  elif event.button_index==MOUSE_BUTTON_RIGHT:
   if event.pressed:dragging=false;teleport_click=false;atlas.open_context(event.position)
   accept_event()
  elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
   set_zoom(zoom*(1.25 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 0.8),event.position);accept_event()
 elif event is InputEventMouseMotion and dragging:
  drag_distance+=event.relative.length()
  center-=event.relative/pixels_per_metre();bound_center();queue_redraw();accept_event()
func _draw()->void:
 draw_rect(Rect2(Vector2.ZERO,size),Color("101e23"))
 var low:=world_to_map(Vector3.ZERO);var edge:=Vector2.ONE*2000*pixels_per_metre()
 if atlas.texture!=null:draw_texture_rect(atlas.texture,Rect2(low,edge),false)
 if atlas.water_survey.texture!=null:draw_texture_rect(atlas.water_survey.texture,Rect2(low,edge),false)
 if atlas.model_survey.texture!=null:draw_texture_rect(atlas.model_survey.drawing_texture,Rect2(low,edge),false)
 if atlas.block_survey.texture!=null:draw_texture_rect(atlas.block_survey.drawing_texture,Rect2(low,edge),false)
 var step:=250 if zoom<4 else 100
 for n in range(0,2001,step):
  var x:=world_to_map(Vector3(n,0,0));var z:=world_to_map(Vector3(0,0,n))
  draw_line(x,x+Vector2(0,edge.y),Color(0.9,0.95,0.8,0.12))
  draw_line(z,z+Vector2(edge.x,0),Color(0.9,0.95,0.8,0.12))
 for road:Dictionary in atlas.roads:
  var a:=world_to_map(road.a);var b:=world_to_map(road.b)
  draw_line(a,b,Color("283439"),maxf(5,road.width*pixels_per_metre()+2),true)
  draw_line(a,b,Color("e7c78c"),maxf(2,road.width*pixels_per_metre()),true)
 label_boxes.clear()
 var font:=ThemeDB.fallback_font
 for deposit:Dictionary in atlas.deposits if atlas.show_deposits else []:
  var at:=world_to_map(deposit.position)
  if not Rect2(Vector2.ZERO,size).grow(-8).has_point(at):continue
  var color:=Color("a9bfd4") if deposit.title.begins_with("Iron") else Color("e5a269")
  draw_circle(at,7,Color("10252b"))
  draw_colored_polygon(PackedVector2Array([at+Vector2(0,-5),at+Vector2(5,0),at+Vector2(0,5),at+Vector2(-5,0)]),color)
  if zoom>=3:
   var title:String=deposit.title.get_slice(" ",0)+" vein"
   var extent:=font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,14)
   var box:=Rect2(at+Vector2(7,-19),extent+Vector2(8,5))
   if Rect2(Vector2.ZERO,size).encloses(box) and not label_boxes.any(func(other):return other.grow(2).intersects(box)):
    label_boxes.append(box);draw_rect(box,Color(.02,.06,.07,.85));draw_string(font,at+Vector2(11,-4),title,HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)
 for place:Dictionary in atlas.places:
  var at:=world_to_map(place.position)
  if not Rect2(Vector2.ZERO,size).grow(-8).has_point(at):continue
  var selected:bool=atlas.game.destination_guide.destination.get("title","")==place.title
  var color:=Color("94e7d0") if selected else Color("e7eee7")
  draw_circle(at,7 if selected else 5,Color("10252b"));draw_circle(at,4 if selected else 3,color)
  var text_size:=font.get_string_size(place.title,HORIZONTAL_ALIGNMENT_LEFT,-1,16)
  for offset:Vector2 in [Vector2(10,-8),Vector2(10,24),Vector2(-text_size.x-10,-8),Vector2(-text_size.x-10,24),Vector2(10,-40),Vector2(10,56)]:
   var text_at:=Vector2(clampf(at.x+offset.x,8,size.x-text_size.x-8),clampf(at.y+offset.y,24,size.y-8))
   var box:=Rect2(text_at+Vector2(-4,-17),text_size+Vector2(8,6))
   if label_boxes.any(func(other):return other.grow(2).intersects(box)):continue
   if atlas.places.any(func(other):return box.grow(5).has_point(world_to_map(other.position))):continue
   label_boxes.append(box);draw_rect(box,Color(0.02,0.06,0.07,0.85))
   draw_string(font,text_at,place.title,HORIZONTAL_ALIGNMENT_LEFT,-1,16,color);break
 for marker:Dictionary in atlas.game.map_markers.markers:
  var at:=world_to_map(Vector3(marker.point.x,0,marker.point.y))
  if not Rect2(Vector2.ZERO,size).grow(-10).has_point(at):continue
  var selected:bool=atlas.game.map_markers.active_id==marker.id
  var color:=Color("f5ca78") if selected else Color("b4cac2")
  draw_circle(at,10 if selected else 8,Color("10252b"))
  draw_colored_polygon(PackedVector2Array([at+Vector2(0,-7),at+Vector2(6,0),at+Vector2(0,7),at+Vector2(-6,0)]),color)
  draw_string(font,at+Vector2(11,5),str(marker.id),HORIZONTAL_ALIGNMENT_LEFT,-1,15,color)
 var player:Vector3=atlas.game.player.global_position;var p:=world_to_map(player)
 var forward:Vector3=-atlas.game.camera.global_basis.z
 var angle:=atan2(forward.x,-forward.z)
 var triangle:=PackedVector2Array()
 for v:Vector2 in [Vector2(0,-13),Vector2(8,9),Vector2(0,5),Vector2(-8,9)]:triangle.append(p+v.rotated(angle))
 draw_circle(p,16,Color(0.02,0.06,0.07,0.7));draw_colored_polygon(triangle,Color("9cffe0"))
 draw_string(font,Vector2(18,30),"N ↑",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
 var bar:float=100 if zoom>=4 else 500
 var end:=Vector2(22+bar*pixels_per_metre(),size.y-24)
 draw_line(Vector2(22,size.y-24),end,Color.WHITE,3)
 draw_string(font,Vector2(22,size.y-36),"%d m"%bar,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color.WHITE)
