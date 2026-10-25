extends SceneTree
const Policy=preload("res://addons/presentation/fullscreen_policy.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var failures:=0
	var original_id:=root.get_window_id()
	var original_handle:=DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,original_id)
	var path:="user://test_graphics_"+str(Time.get_ticks_usec())+".cfg"
	ProjectSettings.set_setting("terraforest/graphics_settings_path",path)
	Policy.apply(root)
	for cycle in 3:
		Policy.set_fullscreen(root,false,false)
		for frame in 5:await process_frame
		var mode:=DisplayServer.window_get_mode()
		var ok:=mode in [DisplayServer.WINDOW_MODE_WINDOWED,DisplayServer.WINDOW_MODE_MAXIMIZED] and not root.borderless
		print("PASS " if ok else "FAIL ","decorated windowed transition ",cycle," mode=",mode)
		if not ok:failures+=1
		Policy.set_fullscreen(root,true,false)
		for frame in 5:await process_frame
		ok=DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN and root.get_window_id()==original_id and DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,original_id)==original_handle and DisplayServer.get_window_list().size()==1
		print("PASS " if ok else "FAIL ","fullscreen returns on the same native window ",cycle)
		if not ok:failures+=1
	Policy.set_fullscreen(root,false,true)
	var resized:=[0];var listener:=func():resized[0]+=1
	root.size_changed.connect(listener);Policy.apply(root)
	for frame in 3:await process_frame
	root.size_changed.disconnect(listener)
	print("PASS " if resized[0]==0 else "FAIL ","startup reapplies saved windowed preference without another resize or fullscreen roundtrip")
	if resized[0]!=0:failures+=1
	var settings:=ConfigFile.new()
	var persisted:=settings.load(path)==OK and not bool(settings.get_value("graphics","fullscreen",true)) and DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_WINDOWED,DisplayServer.WINDOW_MODE_MAXIMIZED]
	print("PASS " if persisted else "FAIL ","windowed preference survives startup policy without touching player settings")
	if not persisted:failures+=1
	Policy.set_fullscreen(root,true,true);Policy.apply(root)
	if DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_FULLSCREEN:failures+=1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("WINDOW_MODES failures=",failures);quit(1 if failures else 0)
