# SPDX-License-Identifier: 0BSD
extends RefCounted
## Generation only. Bounded roadside candidates; no terrain edits or runtime polling.
const NAMES:=["Greyford","Ashbrook","Blackwater","Hollow Creek","Stonebridge","Ravenhill","Pine Hollow","Coldwater","Briarwood","Northwick","Redmarsh","Oakridge","Westmere","Millhaven","Dunvale","Ironwood"]
const HALF_WIDTH:=1.4
static func town_name(seed_value:int,town:int)->String:
	return NAMES[posmod(seed_value+town*7,NAMES.size())]

static func corners(pose:Transform3D,margin:float=0.0)->PackedVector3Array:
	var points:=PackedVector3Array()
	for x:float in [-HALF_WIDTH-margin,HALF_WIDTH+margin]:
		for z:float in [-.13-margin,.13+margin]:points.append(pose*Vector3(x,0,z))
	return points

static func clear(pose:Transform3D,roads:Array,lots:Array)->bool:
	# Include the complete transformed board, road shoulder and a walking margin.
	var envelope:=Rect2(Vector2(pose.origin.x,pose.origin.z),Vector2.ZERO)
	for point:Vector3 in corners(pose,.35):
		if point.x<4 or point.z<4 or point.x>1996 or point.z>1996:return false
		envelope=envelope.expand(Vector2(point.x,point.z))
	var center:=Vector2(pose.origin.x,pose.origin.z)
	for road:Dictionary in roads:
		var a:=Vector2(road.start.x,road.start.z);var b:=Vector2(road.finish.x,road.finish.z)
		# The 1.82 m radius encloses the board plus its .35 m clearance in every yaw.
		if center.distance_to(Geometry2D.get_closest_point_to_segment(center,a,b))<float(road.get("half_width",4))+float(road.get("shoulder",3))+1.0+1.82:return false
	for bounds:AABB in lots:
		if envelope.intersects(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(2.0)):return false
	return true

static func candidates(sites:Array,network:Dictionary)->Dictionary:
	var result:Dictionary={};var roads:Array=network.get("segments",[]).duplicate();var lots:Array=[]
	for site:Dictionary in sites:
		result[int(site.get("town",0))]=[]
		roads.append_array(site.roads)
		for lot:Dictionary in site.lots:
			lots.append(lot.bounds)
			if lot.has("entrance"):roads.append(lot.entrance.segment)
	for town:int in result:
		var approaches:Array=[]
		# External road connections first, then the outer ends of settlement streets.
		for link:Dictionary in network.get("links",[]):
			if link.get("trail",false):continue
			for reverse:bool in [false,true]:
				var index:int=link.target if reverse else link.source
				var other:int=link.source if reverse else link.target
				if index<0 or index>=sites.size() or int(sites[index].get("town",0))!=town:continue
				if other>=0 and other<sites.size() and int(sites[other].get("town",0))==town:continue
				var path:PackedVector3Array=link.points.duplicate()
				if reverse:path.reverse()
				var traveled:=0.0
				for i in range(1,path.size()):
					var span:=path[i].distance_to(path[i-1])
					for distance:float in [12.0,24.0,40.0,60.0]:
						if distance>=traveled and distance<traveled+span:
							approaches.append({"point":path[i-1].lerp(path[i],(distance-traveled)/span),"out":path[i]-path[i-1],"width":4.0,"approach":path[0]})
					traveled+=span
					if traveled>60:break
		for site:Dictionary in sites:
			if int(site.get("town",0))!=town:continue
			for road:Dictionary in site.roads:
				for reverse:bool in [false,true]:
					var end:Vector3=road.finish if reverse else road.start
					var other:Vector3=road.start if reverse else road.finish
					if end.distance_to(site.center)<other.distance_to(site.center):continue
					approaches.append({"point":end.lerp(other,.08),"out":end-other,"width":road.get("half_width",4),"approach":end})
		for entry:Dictionary in approaches:
			var outward:Vector3=entry.out;outward.y=0
			if outward.length_squared()<.01:continue
			outward=outward.normalized()
			var right:=Vector3.UP.cross(outward)
			for side:float in [1.0,-1.0]:
				var pose:=Transform3D(Basis(right,Vector3.UP,outward),entry.point+right*side*(float(entry.width)+6.5))
				if clear(pose,roads,lots):result[town].append({"transform":pose,"approach":entry.approach,"road_height":entry.point.y})
				if result[town].size()>=48:break
			if result[town].size()>=48:break
	return result
