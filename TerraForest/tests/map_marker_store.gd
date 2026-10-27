extends SceneTree

const Markers=preload("res://addons/player_runtime/map_markers.gd")
const Compass=preload("res://addons/player_runtime/compass.gd")
var checks:=0
var failures:=0

func check(condition:bool,label:String)->void:
	checks+=1;print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1

func _initialize()->void:
	var store:=Markers.new()
	check(store.restore_snapshot(PackedByteArray()) and store.markers.is_empty(),"old worlds without a marker section restore an empty default")
	var first:=store.mark(Vector2(123.25,678.5));var second:=store.mark(Vector2(2000,0))
	check(first==1 and second==2 and store.active_id==second,"markers have stable identities and the newest mark becomes active")
	check(store.activate(first) and store.find(first).point==Vector2(123.25,678.5),"old markers can be selected without recreating them")
	var snapshot:=store.capture_snapshot();var restored:=Markers.new()
	check(snapshot.size()==40 and restored.restore_snapshot(snapshot) and restored.capture_snapshot()==snapshot,"binary snapshot retains exact marker positions, identities and active selection")
	var archive:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var packed:PackedByteArray=archive.encode({"terrain":PackedByteArray(),"map_markers_v1":snapshot})
	check(archive.decode(packed).get("sections",{}).get("map_markers_v1",PackedByteArray())==snapshot,"native world archive preserves the marker section")
	var cache:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--derived-cache="):cache=argument.trim_prefix("--derived-cache=")
	var expression:=RegEx.new();expression.compile("^user://map_marker_store_[0-9a-f]{32}$")
	if expression.search(cache)!=null:
		var directory:=ProjectSettings.globalize_path(cache);DirAccess.make_dir_recursive_absolute(directory)
		var path:=directory.path_join("markers.trw")
		check(not FileAccess.file_exists(path) and archive.acquire(path) and archive.publish(path,packed)==OK,"native publisher saves markers only into this test's unique temporary cache")
		var loaded:PackedByteArray=archive.decode(archive.read(path)).get("sections",{}).get("map_markers_v1",PackedByteArray())
		archive.release()
		check(restored.restore_snapshot(loaded) and restored.capture_snapshot()==snapshot,"native disk archive reload retains markers and active navigation")
	else:check(false,"disk roundtrip requires an isolated launcher-owned cache")
	var thread:=Thread.new();thread.start(func():return restored.validate_snapshot(snapshot))
	check(thread.wait_to_finish(),"pure marker validation works on the archive worker thread")
	var damaged:=snapshot.duplicate();damaged.encode_float(20,NAN)
	check(not restored.restore_snapshot(damaged) and restored.capture_snapshot()==snapshot,"nonfinite coordinates reject transactionally")
	damaged=snapshot.duplicate();damaged.encode_u32(28,1)
	check(not restored.restore_snapshot(damaged) and restored.capture_snapshot()==snapshot,"duplicate identities reject transactionally")
	damaged=snapshot.duplicate();damaged.encode_u32(8,999)
	check(not restored.restore_snapshot(damaged),"missing active identity is rejected")
	check(not restored.restore_snapshot(snapshot.slice(0,39)),"truncated binary marker data is rejected")
	check(store.mark(Vector2(-1,0))==0 and store.mark(Vector2(INF,100))==0 and store.mark(Vector2(10,2001))==0,"off-world and nonfinite points do not create markers")
	check(store.unmark(second) and store.active_id==first and store.markers.size()==1,"unmarking an old inactive marker preserves the selected destination")
	check(store.activate(0) and store.find(first).id==first,"stopping navigation preserves the saved marker")
	store.activate(first)
	check(store.unmark(first) and store.active_id==0 and store.markers.is_empty(),"removing the active marker clears navigation")
	for index in Markers.LIMIT:store.mark(Vector2(index,index))
	check(store.markers.size()==64 and store.mark(Vector2(10,20))==0 and store.capture_snapshot().size()==784,"marker storage and rendering work stay bounded at 64 markers")
	check(restored.restore_snapshot(PackedByteArray()) and restored.next_id==1 and restored.active_id==0,"loading a different old world clears previous-world markers")
	check(is_zero_approx(Compass.heading_for(Vector3.FORWARD)) and is_equal_approx(Compass.heading_for(Vector3.RIGHT),PI*.5),"compass north and east agree with the north-up world map")
	check(is_zero_approx(Compass.relative_bearing(Vector3.ZERO,Vector3.RIGHT,Vector3(100,0,0))),"facing the marker centres it on the compass")
	check(Compass.relative_bearing(Vector3.ZERO,Vector3.FORWARD,Vector3(100,0,0))>0 and Compass.relative_bearing(Vector3.ZERO,Vector3.FORWARD,Vector3(-100,0,0))<0,"compass left and right bearings have the correct sign")
	check(absf(Compass.relative_bearing(Vector3.ZERO,Vector3(.001,0,1),Vector3(-.1,0,100)))<.01,"compass bearings wrap smoothly across south")
	print("MAP_MARKER_STORE checks=",checks," failures=",failures);quit(1 if failures else 0)
