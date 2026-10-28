extends RefCounted

const Lots=preload("res://addons/structures/northern_lots.gd")
const Catalog=preload("res://addons/structures/bridge_catalog.gd")

static func build(core:RefCounted,roads:Array,reservations:Array)->Dictionary:
 var sampled:Dictionary=core.plan_lake_crossings()
 if not sampled.get("ok",false):return sampled
 var crossings:=[];var segments:=[];var navigation:=[];var rejected:=[]
 for candidate:Dictionary in sampled.crossings:
  var connections:=[];var joins:=[]
  for anchor:Vector3 in candidate.anchors:
   var targets:=[]
   for road:Dictionary in roads:
    if int(road.get("material",4))!=4:continue
    var axis:Vector3=road.finish-road.start;var flat:=Vector3(axis.x,0,axis.z)
    if flat.length_squared()<1:continue
    var fraction:=clampf(Vector3(anchor.x-road.start.x,0,anchor.z-road.start.z).dot(flat)/flat.length_squared(),0,1)
    var point:Vector3=road.start+axis*fraction
    var distance:=Vector2(point.x-anchor.x,point.z-anchor.z).length()
    if distance>600 or distance<8:continue
    targets.append({"point":point,"distance":distance,"width":road.half_width})
   targets.sort_custom(func(first:Dictionary,second:Dictionary):return first.distance<second.distance)
   var connection:={};var attempts:=PackedVector3Array()
   for target:Dictionary in targets:
    if attempts.size()>=4:break
    var duplicate:=false
    for tried:Vector3 in attempts:duplicate=duplicate or tried.distance_squared_to(target.point)<100
    if duplicate:continue
    attempts.append(target.point)
    connection=core.plan_regional_route(anchor,target.point,reservations)
    if connection.get("ok",false) and compatible_crossings(connection.points,roads):joins.append(float(target.width)+.5);break
    connection={}
   if not connection.get("ok",false):break
   connections.append(connection.points)
  if connections.size()!=2:
   rejected.append({"lake_id":candidate.lake_id,"reason":"No safe connection to both banks"});continue
  candidate["connections"]=connections;crossings.append(candidate)
  segments.append_array(candidate.approaches)
  navigation.append({"a":candidate.banks[0],"b":candidate.banks[1],"width":6.0})
  for approach:Dictionary in candidate.approaches:navigation.append({"a":approach.start,"b":approach.finish,"width":5.0})
  for connection_index in connections.size():
   var points:PackedVector3Array=connections[connection_index]
   for index in range(1,points.size()):
    var finish:Vector3=points[index]
    if index==points.size()-1:
     var length:=Vector2(finish.x-points[index-1].x,finish.z-points[index-1].z).length()
     finish=finish.lerp(points[index-1],minf(1.0,joins[connection_index]/length))
    if finish.distance_squared_to(points[index-1])>1:segments.append(Lots._segment(points[index-1],finish,2.5,3,4,1,1))
    navigation.append({"a":points[index-1],"b":points[index],"width":5.0})
 return {"ok":true,"bridges":crossings,"segments":segments,"navigation":navigation,"rejected":rejected,"height_samples":sampled.height_samples}

static func asset(crossing:Dictionary)->Resource:
 return Catalog.lake_crossing(int(crossing.span))

static func compatible_crossings(points:PackedVector3Array,roads:Array)->bool:
 for index in range(1,points.size()):
  var start:=Vector2(points[index-1].x,points[index-1].z)
  var axis:=Vector2(points[index].x,points[index].z)-start
  for road:Dictionary in roads:
   var other:=Vector2(road.start.x,road.start.z)
   var direction:=Vector2(road.finish.x,road.finish.z)-other
   var divisor:=axis.cross(direction)
   if absf(divisor)<.0001:continue
   var along:=(other-start).cross(direction)/divisor
   var across:=(other-start).cross(axis)/divisor
   if along<0 or along>1 or across<0 or across>1:continue
   if absf(lerpf(points[index-1].y,points[index].y,along)-lerpf(road.start.y,road.finish.y,across))>.15:return false
 return true
