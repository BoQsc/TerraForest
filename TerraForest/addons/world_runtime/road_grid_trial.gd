extends RefCounted
const VERSION:=1
static func segments(source:Array)->Dictionary:
	if source.is_empty() or source.size()>4096:return {"ok":false,"reason":"Invalid trial road count"}
	var planner:RefCounted=ClassDB.instantiate("NativeRoadProfile")
	var result:Array=[]
	var changed:=0
	var maximum_shift:=0.0
	var maximum_grade:=0.0
	for value in source:
		if not value is Dictionary:return {"ok":false,"reason":"Invalid trial road descriptor"}
		var road:Dictionary=value
		for field in ["start","finish","material","half_width","depth","clearance","shoulder"]:
			if not road.has(field):return {"ok":false,"reason":"Incomplete trial road descriptor"}
		if road.material not in [3,4] or road.half_width<2.0:
			result.append(road);continue
		var start:Vector3=road.start
		var finish:Vector3=road.finish
		var spacing:=Vector2(finish.x-start.x,finish.z-start.z).length()
		if spacing<1.0:result.append(road);continue
		var coefficients:PackedFloat64Array=road.get("coefficients",PackedFloat64Array([0,0,finish.y-start.y,start.y]))
		if int(road.get("curve_index",0))<0 or int(road.get("curve_index",0))*4>=coefficients.size():return {"ok":false,"reason":"Invalid trial curve index"}
		var fitted:Dictionary=planner.grid_trial(coefficients,spacing)
		if not fitted.get("ok",false):return fitted
		maximum_shift=maxf(maximum_shift,fitted.max_shift)
		maximum_grade=maxf(maximum_grade,fitted.max_grade)
		if fitted.max_shift<0.001:result.append(road);continue
		changed+=1
		for part in fitted.subdivisions:
			var section:int=int(road.get("curve_index",0))*fitted.subdivisions+part
			var revised:Dictionary=road.duplicate()
			revised.start=start.lerp(finish,float(part)/fitted.subdivisions)
			revised.finish=start.lerp(finish,float(part+1)/fitted.subdivisions)
			revised.start.y=fitted.coefficients[section*4+3]
			revised.finish.y=fitted.coefficients[section*4]+fitted.coefficients[section*4+1]+fitted.coefficients[section*4+2]+fitted.coefficients[section*4+3]
			revised.coefficients=fitted.coefficients
			revised.curve_index=section
			result.append(revised)
		if result.size()>4096:return {"ok":false,"reason":"Trial road subdivision budget exceeded"}
	if result.size()>4096:return {"ok":false,"reason":"Trial road subdivision budget exceeded"}
	return {"ok":true,"segments":result,"changed":changed,"max_shift":maximum_shift,"max_grade":maximum_grade,"version":VERSION}
