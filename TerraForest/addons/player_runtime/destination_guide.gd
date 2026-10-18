# SPDX-License-Identifier: 0BSD
extends CanvasLayer
# Five updates per second while tracking; no world queries, mesh work or per-frame processing.
var game:Node
var destination:Dictionary={}
var panel:PanelContainer
var caption:Label
var timer:Timer
func _ready()->void:
 layer=24
 panel=PanelContainer.new();panel.position=Vector2(710,24);panel.custom_minimum_size=Vector2(500,0);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(panel)
 var style:=StyleBoxFlat.new();style.bg_color=Color(0.025,0.05,0.05,0.86)
 for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(side,10)
 panel.add_theme_stylebox_override("panel",style)
 caption=Label.new();caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;caption.add_theme_font_size_override("font_size",18);panel.add_child(caption)
 timer=Timer.new();timer.wait_time=0.2;timer.timeout.connect(refresh);add_child(timer)
 panel.hide()
func track(place:Dictionary)->bool:
 if not place.has("position") or not place.position is Vector3 or not place.position.is_finite() or str(place.get("title","")).is_empty():return false
 destination={"title":str(place.title),"position":place.position}
 timer.start();refresh();return true
func clear()->void:
 destination.clear();timer.stop();panel.hide()
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
 if destination.is_empty():return
 panel.visible=not game.loading_active and not game.session_menu.visible_ui() and not game.player_hud.inventory_open
 if not panel.visible:return
 var result:=guidance(game.player.global_position,-game.camera.global_basis.z,destination.position)
 var status:="At destination" if result.arrived else "%s · %.0f m"%[result.direction,result.distance]
 if not result.arrived and absf(result.height)>8:status+=" · %.0f m %s"%[absf(result.height),"above" if result.height>0 else "below"]
 caption.text="%s\n%s\nDirect bearing · follow roads and entrances"%[destination.title,status]
