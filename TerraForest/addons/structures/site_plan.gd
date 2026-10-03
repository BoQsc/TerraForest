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
	if asset.get_meta("frontage_version")!=1 or typeof(street)!=TYPE_INT or street<4 or street>64 or street%2!=0:
		return {"ok":false,"reason":"Frontage lacks valid street layout metadata; regenerate the frontage"}
	for point in asset.foundation_samples(Vector3i.ZERO,0,0):
		if absf(point.z)<float(street)*0.5:
			return {"ok":false,"reason":"Street corridor overlaps the building footprint; regenerate the frontage"}
	var local: AABB=asset.placement_bounds(Vector3i.ZERO,0)
	var columns:=ceili(local.size.x/120.0)
	var rows:=ceili(float(street)/24.0)
	if plan.segments.size()+columns*rows>MAX_SEGMENTS:
		return {"ok":false,"reason":"Foundation and street exceed 256 sections; divide the layout"}
	for row in rows:
		for column in columns:
			var z: float=-float(street)*0.5+float(street)*(row+0.5)/rows
			var a:=Vector3(local.position.x+local.size.x*column/columns,0,z)
			var b:=Vector3(local.position.x+local.size.x*(column+1)/columns,0,z)
			for turn in rotation:
				a=Vector3(1-a.z,0,a.x);b=Vector3(1-b.z,0,b.x)
			a+=Vector3(plan.target);b+=Vector3(plan.target)
			var half_width: float=float(street)/rows*0.5
			var low:=a.min(b)-Vector3(half_width,8,half_width)
			var high:=a.max(b)+Vector3(half_width,12,half_width)
			if low.x<5 or low.z<5 or high.x>1995 or high.z>1995:
				return {"ok":false,"reason":"Street paving reaches world boundary"}
			var region:=AABB(low,high-low)
			plan.bounds=plan.bounds.merge(region)
			plan.segments.append({"start":a,"finish":b,"half_width":half_width,"depth":8.0,"clearance":12.0,"shoulder":0.0,"material":4,"bounds":region})
	plan.paving_segments=columns*rows;plan["street_width"]=street
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
