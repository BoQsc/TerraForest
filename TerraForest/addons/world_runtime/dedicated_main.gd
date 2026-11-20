# SPDX-License-Identifier: 0BSD
extends SceneTree
## Trusted operator control over inherited process pipes. No network listener.
const World=preload("res://addons/world_runtime/dedicated_world.gd")
var world:=World.new()

func _initialize()->void:run.call_deferred()

func run()->void:
	var slot:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--authority-slot="):slot=arg.trim_prefix("--authority-slot=")
	if DisplayServer.get_name()!="headless" or not world.open(slot):
		printerr("Headless authority could not acquire or restore its world");quit(1);return
	print("AUTHORITY ",JSON.stringify({"ready":true,"revision":world.revision(),"last_request_id":world.last_request_id()}))
	var pending:=""
	while true:
		# A larger blocking read on a Windows pipe may wait for another command.
		var next:=OS.read_buffer_from_stdin(1)
		if next.is_empty():break
		if next[0]==10:
			var line:=pending.strip_edges()
			if line=="quit":break
			print("AUTHORITY ",JSON.stringify(command(line.split(" ",false))))
			pending=""
		elif next[0]!=13:
			if next[0]<32 or next[0]>126 or pending.length()>=256:
				printerr("Invalid operator command");world.archive.release();quit(2);return
			pending+=String.chr(next[0])
	world.archive.release()
	quit()

func command(args:PackedStringArray)->Dictionary:
	if args==PackedStringArray(["edit-profile"]):return {"ok":true,"profile":world.last_edit_profile}
	if args==PackedStringArray(["v1","inventory"]):
		var state:Dictionary=world.inventory.snapshot()
		return {"ok":true,"version":1,"slots":state.slots,"session_revision":state.revision}
	if args.size()==8 and args[0]=="v1" and args[1]=="water-surface":
		for index in range(2,8):
			if not args[index].is_valid_float():return {"ok":false,"reason":"Invalid position"}
		return world.water_surface(Vector3(float(args[2]),float(args[3]),float(args[4])),Vector3(float(args[5]),float(args[6]),float(args[7])))
	if args.size()>=2 and args[0]=="v1" and args[1]=="sample":
		var coordinates:=args.size()-2
		if coordinates==0 or coordinates%3!=0 or coordinates>3*World.MAX_QUERY_POINTS:return {"ok":false,"reason":"Invalid point count"}
		var points:=PackedVector3Array()
		for index in range(2,args.size(),3):
			for axis in 3:
				if not args[index+axis].is_valid_float():return {"ok":false,"reason":"Invalid position"}
			points.append(Vector3(float(args[index]),float(args[index+1]),float(args[index+2])))
		return world.sample_points(points)
	var request_id:=0
	if args.size()>=3 and args[0]=="v1" and ((args.size()==8 and args[2]=="excavate") or (args.size()==9 and args[2]=="deposit")):
		if not args[1].is_valid_int():return {"ok":false,"reason":"Invalid request ID"}
		request_id=int(args[1])
		if request_id<1 or request_id>0xffffffff:return {"ok":false,"reason":"Invalid request ID"}
		args=args.slice(2)
	if args==PackedStringArray(["save"]):return {"ok":world.save(),"revision":world.revision()}
	if args==PackedStringArray(["lakes"]):
		var definitions:Dictionary=ClassDB.instantiate("NativeLakeCatalog").decode(world.catalog)
		return {"ok":true,"lakes":definitions.records}
	if args.size() not in [4,6,7]:return {"ok":false,"reason":"Unknown command"}
	for index in range(1,4):
		if not args[index].is_valid_float():return {"ok":false,"reason":"Invalid position"}
	var point:=Vector3(float(args[1]),float(args[2]),float(args[3]))
	if not point.is_finite():return {"ok":false,"reason":"Invalid position"}
	if args.size()==4 and args[0]=="sample":return world.sample(point)
	if args.size()==6 and args[0]=="excavate" and args[4].is_valid_float() and args[5].is_valid_int():
		return world.excavate(point,float(args[4]),int(args[5]),request_id)
	if args.size()==7 and request_id>0 and args[0]=="deposit" and args[4].is_valid_float() and args[5].is_valid_int() and args[6].is_valid_int():
		return world.deposit(point,float(args[4]),int(args[5]),int(args[6]),request_id)
	return {"ok":false,"reason":"Unknown command"}
