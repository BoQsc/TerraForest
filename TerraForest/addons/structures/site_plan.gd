# SPDX-License-Identifier: 0BSD
extends RefCounted
# Infrequent authoring geometry only. Terrain evaluation and edits stay native.
# The complete plan must pass protection checks before any segment is applied.
const MAX_SEGMENTS:=256
static func prepare(asset: Resource,origin: Vector3i,rotation: int,grade: int) -> Dictionary:
	var plan:=foundation(asset,origin,rotation,grade)
	if not plan.ok: return plan
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
	return plan

static func foundation(asset: Resource,origin: Vector3i,rotation: int,grade: int) -> Dictionary:
	if asset==null or not asset.is_class("NativeBlockPrefab") or rotation<0 or rotation>3:
		return {"ok":false,"reason":"Invalid building layout"}
	var target:=Vector3i(origin.x,grade,origin.z)
	var bounds: AABB=asset.placement_bounds(target,rotation)
	if bounds.position.y!=grade:
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
