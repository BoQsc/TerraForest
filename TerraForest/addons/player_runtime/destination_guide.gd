# SPDX-License-Identifier: 0BSD
extends CanvasLayer
var game:Node
var destination:Dictionary={}
var panel:PanelContainer
var caption:Label
var timer:Timer
var compass:Control
func _ready()->void:
 layer=24
 compass=preload("res://addons/player_runtime/compass.gd").new();add_child(compass)
 panel=PanelContainer.new();panel.custom_minimum_size=Vector2(500,0);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(panel)
 var style:=StyleBoxFlat.new();style.bg_color=Color(0.025,0.05,0.05,0.86)
 for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(side,10)
 panel.add_theme_stylebox_override("panel",style)
 caption=Label.new();caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;caption.add_theme_font_size_override("font_size",18);panel.add_child(caption)
 timer=Timer.new();timer.wait_time=0.2;timer.timeout.connect(refresh);add_child(timer)
 game.map_markers.changed.connect(sync_marker);get_viewport().size_changed.connect(layout)
 layout();sync_marker();panel.hide();compass.hide()
func layout()->void:
 var dimensions:=get_viewport().get_visible_rect().size
 compass.size=Vector2(minf(620,dimensions.x-36),58);compass.position=Vector2((dimensions.x-compass.size.x)*.5,28)
 panel.position=Vector2((dimensions.x-500)*.5,92)
func _process(_delta:float)->void:
 var showing:bool=not game.loading_active and not game.shutdown_requested and not game.session_menu.visible_ui() and not game.player_hud.inventory_open
 compass.visible=showing;panel.visible=showing and not destination.is_empty()
 if showing:compass.update_view(game.player.global_position,-game.camera.global_basis.z,destination)
func sync_marker()->void:
 if game.map_markers.active_id>0:destination=game.map_markers.describe(game.map_markers.active_id)
 elif destination.has("marker_id"):destination.clear()
 refresh()
func track(place:Dictionary)->bool:
 if not place.has("position") or not place.position is Vector3 or not place.position.is_finite() or str(place.get("title","")).is_empty():return false
 var identity:int=place.get("marker_id",0)
 if identity!=0 and game.map_markers.find(identity).is_empty():return false
 destination=place.duplicate(true);destination.title=str(place.title)
 game.map_markers.activate(identity);refresh();return true
func clear()->void:
 destination.clear();game.map_markers.activate(0);timer.stop();panel.hide()
static func guidance(at:Vector3,facing:Vector3,target:Vector3)->Dictionary:
 var delta:=target-at
 var distance:=Vector2(delta.x,delta.z).length()
 var angle:=wrapf(atan2(delta.x,-delta.z)-atan2(facing.x,-facing.z),-PI,PI)
 var direction:="Ahead"
 if absf(angle)>PI*0.75:direction="Behind you"
 elif angle>PI/8:direction="Turn right"
 elif angle< -PI/8:direction="Turn left"
 var arrived:bool=distance<=12 and absf(delta.y)<=8
 return {"distance":distance,"direction":direction,"arrived":arrived,"height":delta.y}
func refresh()->void:
 if destination.is_empty():timer.stop();panel.hide();return
 if timer.is_stopped():timer.start()
 panel.visible=not game.loading_active and not game.session_menu.visible_ui() and not game.player_hud.inventory_open
 if not panel.visible:return
 var target:Vector3=destination.position
 if destination.has("marker_id"):target.y=game.player.global_position.y
 var result:=guidance(game.player.global_position,-game.camera.global_basis.z,target)
 var status:="At destination" if result.arrived else "%s · %.0f m"%[result.direction,result.distance]
 if not result.arrived and absf(result.height)>8:status+=" · %.0f m %s"%[absf(result.height),"above" if result.height>0 else "below"]
 caption.text="%s · %s"%[destination.title,status]
 caption.tooltip_text="Direct bearing only · follow roads and entrances"
