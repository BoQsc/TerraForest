extends Control

var heading:=0.0
var bearing:=0.0
var has_marker:=false
var contacts:=PackedVector2Array()
var pulse:=false

static func heading_for(facing:Vector3)->float:
	return atan2(facing.x,-facing.z)

static func relative_bearing(at:Vector3,facing:Vector3,target:Vector3)->float:
	return wrapf(heading_for(target-at)-heading_for(facing),-PI,PI)

func update_view(at:Vector3,facing:Vector3,destination:Dictionary,targets:Array=[])->void:
	var next_heading:=heading_for(facing) if Vector2(facing.x,facing.z).length_squared()>.00001 else heading
	var next_marker:bool=not destination.is_empty() and not destination.get("area",false)
	var next_bearing:=wrapf(heading_for(destination.position-at)-next_heading,-PI,PI) if next_marker else 0.0
	var next_contacts:=PackedVector2Array()
	next_contacts.resize(mini(targets.size(),32))
	for index in next_contacts.size():
		var target:Dictionary=targets[index]
		next_contacts[index]=Vector2(wrapf(heading_for(target.position-at)-next_heading,-PI,PI),1 if target.sleeping else 0)
	var next_pulse:=int(Time.get_ticks_msec()/450)%2==0
	if absf(wrapf(next_heading-heading,-PI,PI))<.001 and next_marker==has_marker and absf(wrapf(next_bearing-bearing,-PI,PI))<.001 and next_contacts==contacts and (contacts.is_empty() or next_pulse==pulse):return
	contacts=next_contacts;pulse=next_pulse
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
	for contact:Vector2 in contacts:
		var center:=Vector2(middle+clampf(contact.x/(PI*.5),-1,1)*reach,47)
		var color:=Color("f2c95e") if contact.y>0 else Color("f2514f")
		if contact.y==0 and not pulse:color.a=.35
		draw_circle(center,6,Color(.04,.02,.02,.85));draw_circle(center,4.5,color)
		draw_circle(center+Vector2(-1.2,-1.3),1.6,Color(1,.94,.85,color.a*.7))
		if absf(contact.x)>PI*.5:draw_line(center+Vector2(7*signf(contact.x),-3),center+Vector2(10*signf(contact.x),0),color,1.5,true)
	if not has_marker:return
	var marker:=Vector2(middle+marker_offset(),47);var color:=Color("f5ca78")
	if absf(bearing)>PI*.5:
		var direction:=1.0 if bearing>0 else -1.0
		draw_colored_polygon(PackedVector2Array([marker+Vector2(6*direction,0),marker+Vector2(-4*direction,-5),marker+Vector2(-4*direction,5)]),color)
	else:draw_colored_polygon(PackedVector2Array([marker+Vector2(0,-5),marker+Vector2(5,0),marker+Vector2(0,5),marker+Vector2(-5,0)]),color)
