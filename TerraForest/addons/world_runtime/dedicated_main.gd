# SPDX-License-Identifier: 0BSD
extends SceneTree
## Trusted operator control over inherited process pipes. No network listener.
const World=preload("res://addons/world_runtime/dedicated_world.gd")
var world:=World.new()
const TICK_HZ:=30
const QUEUE_CAPACITY:=32
const WORK_BUDGET_US:=26667
var reader:=Thread.new()
var queue_mutex:=Mutex.new()
var free_slots:=Semaphore.new()
var inbox:Array[Dictionary]=[]
var tick_count:=0
var peak_tick_us:=0
var over_budget_ticks:=0
const TICK_HISTORY:=256
var tick_work_us:=PackedInt64Array()

func _initialize()->void:run.call_deferred()

func run()->void:
	var slot:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--authority-slot="):slot=arg.trim_prefix("--authority-slot=")
	if DisplayServer.get_name()!="headless" or not world.open(slot):
		printerr("Headless authority could not acquire or restore its world");quit(1);return
	Engine.physics_ticks_per_second=TICK_HZ
	Engine.max_fps=TICK_HZ
	tick_work_us.resize(TICK_HISTORY)
	for slot_index in QUEUE_CAPACITY:free_slots.post()
	if reader.start(_read_operator)!=OK:
		world.archive.release();quit(1);return
	physics_frame.connect(_tick)
	print("AUTHORITY ",JSON.stringify({"ready":true,"revision":world.revision(),"last_request_id":world.last_request_id()}))

func _enqueue(message:Dictionary)->void:
	free_slots.wait()
	queue_mutex.lock()
	inbox.append(message)
	queue_mutex.unlock()

func _read_operator()->void:
	var pending:=""
	while true:
		# A larger blocking read on a Windows pipe may wait for another command.
		var next:=OS.read_buffer_from_stdin(1)
		if next.is_empty():
			_enqueue({"exit":0});return
		if next[0]==10:
			var line:=pending.strip_edges()
			if line=="quit":
				_enqueue({"exit":0});return
			_enqueue({"line":line})
			pending=""
		elif next[0]!=13:
			if next[0]<32 or next[0]>126 or pending.length()>=256:
				_enqueue({"exit":2});return
			pending+=String.chr(next[0])

func _tick()->void:
	var started:=Time.get_ticks_usec()
	tick_count+=1
	for index in QUEUE_CAPACITY:
		queue_mutex.lock()
		var message:Dictionary={} if inbox.is_empty() else inbox.pop_front()
		queue_mutex.unlock()
		if message.is_empty():break
		free_slots.post()
		if message.has("exit"):
			reader.wait_to_finish()
			world.archive.release()
			if message.exit!=0:printerr("Invalid operator command")
			quit(message.exit);return
		print("AUTHORITY ",JSON.stringify(command(message.line.split(" ",false))))
		if Time.get_ticks_usec()-started>=WORK_BUDGET_US:break
	var elapsed:=Time.get_ticks_usec()-started
	tick_work_us[(tick_count-1)%TICK_HISTORY]=elapsed
	peak_tick_us=maxi(peak_tick_us,elapsed)
	if elapsed>WORK_BUDGET_US:over_budget_ticks+=1

func command(args:PackedStringArray)->Dictionary:
	if args==PackedStringArray(["tick-profile"]):
		var samples:=tick_work_us.slice(0,mini(tick_count-1,TICK_HISTORY))
		samples.sort()
		var p99:=0 if samples.is_empty() else samples[ceili(samples.size()*0.99)-1]
		return {"ok":true,"hz":TICK_HZ,"tick":tick_count,"peak_tick_us":peak_tick_us,"over_budget_ticks":over_budget_ticks,"samples":samples.size(),"p99_work_us":p99}
	if args==PackedStringArray(["edit-profile"]):return {"ok":true,"profile":world.last_edit_profile}
	if args==PackedStringArray(["v1","inventory"]):
		var state:Dictionary=world.inventory.snapshot()
		return {"ok":true,"version":1,"slots":state.slots,"session_revision":state.revision,"digest":world.inventory_digest().hex_encode()}
	if args.size()==7 and args[0]=="v1" and args[2]=="move-stack":
		for index in [1,3,4,5]:
			if not args[index].is_valid_int():return {"ok":false,"reason":"Invalid inventory move"}
		return world.move_stack(int(args[1]),int(args[3]),int(args[4]),int(args[5]),args[6])
	if args.size()==12 and args[0]=="v1" and args[2] in ["scoop","pour"]:
		for index in [1,9,10]:
			if not args[index].is_valid_int():return {"ok":false,"reason":"Invalid bucket request"}
		for index in range(3,9):
			if not args[index].is_valid_float():return {"ok":false,"reason":"Invalid position"}
		return world.transfer_bucket(int(args[1]),args[2]=="pour",Vector3(float(args[3]),float(args[4]),float(args[5])),Vector3(float(args[6]),float(args[7]),float(args[8])),int(args[9]),int(args[10]),args[11])
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
