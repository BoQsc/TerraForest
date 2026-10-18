# SPDX-License-Identifier: 0BSD
extends RefCounted
# Infrequent authoring geometry only. Terrain evaluation and edits stay native.
# The complete plan must pass protection checks before any segment is applied.
const MAX_SEGMENTS:=256
static func prepare(asset: Resource,origin: Vector3i,rotation: int,grade: int) -> Dictionary:
	var plan:=foundation(asset,origin,rotation,grade)
	if not plan.ok: return plan
	if asset.get_meta("cellar_clearance",false):
		for x in [-2,0,2]:
			var a:=Vector3(x,1,-3);var b:=Vector3(x,1,3)
			for turn in rotation:
				a=Vector3(1-a.z,a.y,a.x);b=Vector3(1-b.z,b.y,b.x)
			a+=Vector3(plan.target);b+=Vector3(plan.target)
			var region:=AABB(a.min(b)-Vector3(1.5,1,1.5),a.max(b)-a.min(b)+Vector3(3,6,3))
			plan.segments.append({"start":a,"finish":b,"half_width":1.5,"depth":1.0,"clearance":5.0,"shoulder":0.0,"material":1,"bounds":region})
			plan.bounds=plan.bounds.merge(region)
	plan["foundation_segments"]=plan.segments.size();plan["paving_segments"]=0
	if not asset.has_meta("frontage_version"): return plan
	var street: Variant=asset.get_meta("street_width",null)
	var version: Variant=asset.get_meta("frontage_version")
	if version not in [1,2] or typeof(street)!=TYPE_INT or street<4 or street>64 or street%2!=0:
		return {"ok":false,"reason":"Layout lacks valid street metadata; regenerate it"}
	var local: AABB=asset.placement_bounds(Vector3i.ZERO,0)
	var lines: PackedVector3Array
	if version==1:
		lines=PackedVector3Array([Vector3(local.position.x,0,0),Vector3(local.end.x,0,0)])
	else:
		var value: Variant=asset.get_meta("street_lines",null)
		if typeof(value)!=TYPE_PACKED_VECTOR3_ARRAY or value.size()<8 or value.size()>20 or value.size()%2!=0:
			return {"ok":false,"reason":"Invalid settlement street segments"}
		lines=value
	var support: PackedVector3Array=asset.foundation_samples(Vector3i.ZERO,0,0)
	var world_lines:=PackedVector3Array()
	for i in range(0,lines.size(),2):
		var a:=lines[i];var b:=lines[i+1]
		if not a.is_finite() or not b.is_finite() or maxf(maxf(absf(a.x),absf(a.z)),maxf(absf(b.x),absf(b.z)))>8192 or a.y!=0 or b.y!=0 or a.distance_to(b)<1 or (a.x!=b.x and a.z!=b.z):
			return {"ok":false,"reason":"Settlement streets must be finite, level and axis-aligned"}
		var direction:=b-a
		for point in support:
			point.y=0
			var nearest:=a+direction*clampf((point-a).dot(direction)/direction.length_squared(),0,1)
			if point.distance_to(nearest)<float(street)*0.5+0.5:
				return {"ok":false,"reason":"Street corridor overlaps the building footprint; regenerate the layout"}
		var columns:=ceili(a.distance_to(b)/120.0)
		var strips:=ceili(float(street)/24.0)
		if plan.segments.size()+columns*strips>MAX_SEGMENTS:
			return {"ok":false,"reason":"Foundation and streets exceed 256 sections; divide the layout"}
		var across:=Vector3(-direction.z,0,direction.x).normalized()
		for strip in strips:
			for column in columns:
				var offset:=across*(-float(street)*0.5+float(street)*(strip+0.5)/strips)
				var start:=a.lerp(b,float(column)/columns)+offset
				var finish:=a.lerp(b,float(column+1)/columns)+offset
				for turn in rotation:
					start=Vector3(1-start.z,0,start.x);finish=Vector3(1-finish.z,0,finish.x)
				start+=Vector3(plan.target);finish+=Vector3(plan.target)
				var half_width: float=float(street)/strips*0.5
				var low:=start.min(finish)-Vector3(half_width,8,half_width)
				var high:=start.max(finish)+Vector3(half_width,12,half_width)
				if low.x<5 or low.z<5 or high.x>1995 or high.z>1995:
					return {"ok":false,"reason":"Street paving reaches world boundary"}
				var region:=AABB(low,high-low)
				plan.bounds=plan.bounds.merge(region)
				plan.segments.append({"start":start,"finish":finish,"half_width":half_width,"depth":8.0,"clearance":12.0,"shoulder":0.0,"material":4,"bounds":region})
		for point in [a,b]:
			for turn in rotation: point=Vector3(1-point.z,0,point.x)
			world_lines.append(point+Vector3(plan.target))
	plan.paving_segments=plan.segments.size()-plan.foundation_segments
	plan["street_width"]=street;plan["street_lines"]=world_lines
	plan["street_ends"]=world_lines.slice(0,2)
	if asset.get_meta("entrance_paths",false):
		return _entrance_paths(asset,plan,lines,rotation,grade)
	return plan

static func foundation(asset: Resource,origin: Vector3i,rotation: int,grade: int) -> Dictionary:
	if asset==null or not asset.is_class("NativeBlockPrefab") or rotation<0 or rotation>3:
		return {"ok":false,"reason":"Invalid building layout"}
	var surface_offset:int=asset.get_meta("site_surface_offset",0)
	if surface_offset not in [0,5] or (surface_offset==5 and not asset.get_meta("cellar_clearance",false)):
		return {"ok":false,"reason":"Invalid underground foundation metadata"}
	var target:=Vector3i(origin.x,grade-surface_offset,origin.z)
	var bounds: AABB=asset.placement_bounds(target,rotation)
	if bounds.position.y!=grade-surface_offset:
		return {"ok":false,"reason":"Foundation layout must have its base at local Y=0"}
	if bounds.size.x<=0 or bounds.size.z<=0 or grade<12 or grade>238:
		return {"ok":false,"reason":"Foundation outside grading limits"}
	# Sweep the longer horizontal dimension. Overlapping capsule ends cover
	# every corner of the rectangle, including rotated and negative local bounds.
	var along_x:=bounds.size.x>=bounds.size.z
	var length: float=bounds.size.x if along_x else bounds.size.z
	var breadth: float=bounds.size.z if along_x else bounds.size.x
	var columns:=ceili(length/120.0)
	var rows:=ceili(breadth/24.0)
	if columns*rows>MAX_SEGMENTS:
		return {"ok":false,"reason":"Site exceeds 256 grading segments; divide the layout"}
	var half_width:=maxf(0.5,breadth/rows*0.5)
	var segments: Array[Dictionary]=[]
	var protection:=AABB()
	for row in rows:
		for column in columns:
			var a:=Vector3(bounds.position.x,grade,bounds.position.z)
			var b:=a
			var start: float=length*column/columns
			var finish: float=maxf(start+1.0,length*(column+1)/columns)
			var across: float=breadth*(row+0.5)/rows
			if along_x:
				a.x+=start;b.x+=finish;a.z+=across;b.z+=across
			else:
				a.z+=start;b.z+=finish;a.x+=across;b.x+=across
			var extent:=half_width+8.0
			var low:=a.min(b)-Vector3(extent,8,extent)
			var high:=a.max(b)+Vector3(extent,12,extent)
			if low.x<5 or low.z<5 or high.x>1995 or high.z>1995:
				return {"ok":false,"reason":"Foundation shoulders reach world boundary"}
			var region:=AABB(low,high-low)
			protection=region if segments.is_empty() else protection.merge(region)
			segments.append({"start":a,"finish":b,"half_width":half_width,"depth":8.0,"clearance":12.0,"shoulder":8.0,"material":1,"bounds":region})
	return {"ok":true,"target":target,"rotation":rotation,"bounds":protection,"segments":segments}


static func _entrance_paths(asset:Resource,plan:Dictionary,lines:PackedVector3Array,rotation:int,grade:int)->Dictionary:
	# Offline authoring only: discover the end of each stair approach from cells.
	var occupied:Dictionary={}
	var records:PackedInt32Array=asset.get_records()
	for i in range(0,records.size(),4):
		occupied[Vector2i(records[i],records[i+2])]=true
	plan["entrance_paths"]=0
	for model:Dictionary in asset.get_model_attachments():
		if model.model!="architecture/wooden_door/v1":continue
		var pose:Transform3D=model.transform
		var forward:=pose.basis.z.normalized()
		var start:=pose.origin+pose.basis.x.normalized()*0.5
		start.y=0
		var found:=false
		for step in range(1,33):
			var candidate:=start+forward*(step*0.5)
			var clear:=true
			for lateral in [-0.7,0.0,0.7]:
				var p:Vector3=candidate+pose.basis.x.normalized()*lateral
				clear=clear and not occupied.has(Vector2i(floori(p.x),floori(p.z)))
			if clear:start=candidate+forward*0.75;found=true;break
		if not found:return {"ok":false,"reason":"Entrance has no clear approach"}
		var finish:=Vector3.INF
		var best:=INF
		for i in range(0,lines.size(),2):
			var span:=lines[i+1]-lines[i]
			var near:=lines[i]+span*clampf((start-lines[i]).dot(span)/span.length_squared(),0,1)
			var offset:=near-start
			if offset.dot(forward)<=0 or absf(offset.dot(pose.basis.x.normalized()))>0.1:continue
			if offset.length()<best:best=offset.length();finish=near
		if not finish.is_finite() or best>32:return {"ok":false,"reason":"Entrance does not face a nearby street"}
		if plan.segments.size()>=MAX_SEGMENTS:return {"ok":false,"reason":"Entrance paths exceed site segment budget"}
		for turn in rotation:
			start=Vector3(1-start.z,0,start.x);finish=Vector3(1-finish.z,0,finish.x)
		start+=Vector3(plan.target);finish+=Vector3(plan.target)
		start.y=grade;finish.y=grade
		var low:=start.min(finish)-Vector3(0.75,2,0.75)
		var high:=start.max(finish)+Vector3(0.75,3,0.75)
		if low.x<5 or low.z<5 or high.x>1995 or high.z>1995:return {"ok":false,"reason":"Entrance path reaches world boundary"}
		var region:=AABB(low,high-low)
		plan.bounds=plan.bounds.merge(region)
		plan.segments.append({"start":start,"finish":finish,"half_width":0.75,"depth":2.0,"clearance":3.0,"shoulder":0.0,"material":4,"bounds":region})
		plan.entrance_paths+=1;plan.paving_segments+=1
	return plan
