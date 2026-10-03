# SPDX-License-Identifier: 0BSD
extends RefCounted
# Infrequent authoring geometry only. Terrain evaluation and edits stay native.
# The complete plan must pass protection checks before any segment is applied.
const MAX_SEGMENTS:=256
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
