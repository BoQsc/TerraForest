extends RefCounted

signal changed
signal edited
const LIMIT=64
const MAGIC=0x4b4d4654
var markers:Array[Dictionary]=[]
var active_id:=0
var next_id:=1

static func valid_point(point:Vector2)->bool:
	return point.is_finite() and point.x>=0 and point.x<=2000 and point.y>=0 and point.y<=2000

func prepare(persistence:RefCounted)->bool:
	return persistence.register_component("map_markers_v1",capture_snapshot,restore_snapshot,self,PackedByteArray())

func find(identity:int)->Dictionary:
	for marker in markers:
		if marker.id==identity:return marker
	return {}

func describe(identity:int)->Dictionary:
	var marker:=find(identity)
	return {} if marker.is_empty() else {"marker_id":identity,"title":"Marker %d"%identity,"position":Vector3(marker.point.x,0,marker.point.y)}

func mark(point:Vector2)->int:
	if not valid_point(point) or markers.size()>=LIMIT or next_id>=0x7fffffff:return 0
	var identity:=next_id;next_id+=1
	markers.append({"id":identity,"point":point});active_id=identity
	changed.emit();edited.emit();return identity

func activate(identity:int)->bool:
	if identity!=0 and find(identity).is_empty():return false
	if active_id!=identity:active_id=identity;changed.emit();edited.emit()
	return true

func unmark(identity:int)->bool:
	for index in markers.size():
		if markers[index].id==identity:
			markers.remove_at(index)
			if active_id==identity:active_id=0
			changed.emit();edited.emit();return true
	return false

func capture_snapshot()->PackedByteArray:
	var data:=PackedByteArray();data.resize(16+markers.size()*12)
	data.encode_u32(0,MAGIC);data.encode_u32(4,next_id);data.encode_u32(8,active_id);data.encode_u32(12,markers.size())
	for index in markers.size():
		var offset:=16+index*12;var marker:Dictionary=markers[index]
		data.encode_u32(offset,marker.id);data.encode_float(offset+4,marker.point.x);data.encode_float(offset+8,marker.point.y)
	return data

static func decode(data:PackedByteArray)->Dictionary:
	if data.is_empty():return {"next":1,"active":0,"markers":[]}
	if data.size()<16 or data.decode_u32(0)!=MAGIC:return {}
	var count:=data.decode_u32(12);var following:=data.decode_u32(4);var selected:=data.decode_u32(8)
	if count>LIMIT or data.size()!=16+count*12 or following<1 or following>0x7fffffff:return {}
	var decoded:Array[Dictionary]=[];var identities:Dictionary={}
	for index in count:
		var offset:=16+index*12;var identity:=data.decode_u32(offset)
		var point:=Vector2(data.decode_float(offset+4),data.decode_float(offset+8))
		if identity<1 or identity>=following or identities.has(identity) or not valid_point(point):return {}
		identities[identity]=true;decoded.append({"id":identity,"point":point})
	if selected!=0 and not identities.has(selected):return {}
	return {"next":following,"active":selected,"markers":decoded}

func validate_snapshot(data:PackedByteArray)->bool:
	return not decode(data).is_empty()

func restore_snapshot(data:PackedByteArray)->bool:
	var decoded:=decode(data)
	if decoded.is_empty():return false
	markers.assign(decoded.markers);next_id=decoded.next;active_id=decoded.active;changed.emit();return true
