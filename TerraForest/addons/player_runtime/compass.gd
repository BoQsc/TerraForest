extends Control

var heading:=0.0
var bearing:=0.0
var has_marker:=false

static func heading_for(facing:Vector3)->float:
	return atan2(facing.x,-facing.z)

static func relative_bearing(at:Vector3,facing:Vector3,target:Vector3)->float:
	return wrapf(heading_for(target-at)-heading_for(facing),-PI,PI)

func update_view(at:Vector3,facing:Vector3,destination:Dictionary)->void:
	var next_heading:=heading_for(facing) if Vector2(facing.x,facing.z).length_squared()>.00001 else heading
	var next_marker:=not destination.is_empty()
	var next_bearing:=wrapf(heading_for(destination.position-at)-next_heading,-PI,PI) if next_marker else 0.0
	if absf(wrapf(next_heading-heading,-PI,PI))<.001 and next_marker==has_marker and absf(wrapf(next_bearing-bearing,-PI,PI))<.001:return
	heading=next_heading;bearing=next_bearing;has_marker=next_marker;queue_redraw()

func marker_offset()->float:
	return clampf(bearing/(PI*.5),-1,1)*(size.x*.5-18)

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE

func _draw()->void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(.025,.045,.05,.72))
	var middle:=size.x*.5;var reach:=middle-18;var font:=ThemeDB.fallback_font
	var names:=["N","NE","E","SE","S","SW","W","NW"]
	for degree in range(0,360,15):
		var angle:=wrapf(deg_to_rad(degree)-heading,-PI,PI)
		if absf(angle)>PI*.5:continue
		var horizontal:=middle+angle/(PI*.5)*reach
		var major:=degree%45==0
		draw_line(Vector2(horizontal,28),Vector2(horizontal,38 if major else 33),Color(.82,.9,.87,.8),1,true)
		if major:
			var title:String=names[int(degree/45.0)];var width:=font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
			draw_string(font,Vector2(horizontal-width*.5,22),title,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("9cffe0") if degree%90==0 else Color("ced9d5"))
	draw_colored_polygon(PackedVector2Array([Vector2(middle-4,0),Vector2(middle+4,0),Vector2(middle,6)]),Color("eff6ef"))
	if not has_marker:return
	var marker:=Vector2(middle+marker_offset(),47);var color:=Color("f5ca78")
	if absf(bearing)>PI*.5:
		var direction:=1.0 if bearing>0 else -1.0
		draw_colored_polygon(PackedVector2Array([marker+Vector2(6*direction,0),marker+Vector2(-4*direction,-5),marker+Vector2(-4*direction,5)]),color)
	else:draw_colored_polygon(PackedVector2Array([marker+Vector2(0,-5),marker+Vector2(5,0),marker+Vector2(0,5),marker+Vector2(-5,0)]),color)
