extends SceneTree
func _initialize()->void:
	var task=load("res://tests/paving_generation_task.gd").new();task.root=root
	task.qualification="--reopen-terrain-lots" in OS.get_cmdline_user_args()
	task.finished.connect(func(code:int):print("PAVING_GENERATION failures=",0 if code==0 else 1);quit(code))
	root.add_child(task)
