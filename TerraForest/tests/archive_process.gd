extends SceneTree
var archive: RefCounted
var path: String
var mode: String
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--archive-path="): path = arg.substr(15)
		if arg.begins_with("--archive-mode="): mode = arg.substr(15)
	call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	archive = ClassDB.instantiate("NativeWorldArchive")
	if mode == "probe":
		var rejected: bool = not archive.acquire(path)
		print("PROBE_OK" if rejected else "PROBE_FAIL")
		quit(0 if rejected else 1)
		return
	if not archive.acquire(path):
		quit(2)
		return
	if mode == "verify":
		var current: Dictionary = archive.decode(archive.read(path))
		var backup: Dictionary = archive.decode(archive.read(path+".bak"))
		var ok: bool = current.get("ok",false) and backup.get("ok",false)
		if ok:
			ok = current["sections"]["terrain"].size()==8*1024*1024 and backup["sections"]["terrain"].size()==8*1024*1024
		print("RECOVERY_OK" if ok else "RECOVERY_FAIL")
		archive.release()
		quit(0 if ok else 1)
		return
	var data := PackedByteArray()
	data.resize(8*1024*1024)
	data.fill(0)
	for i in range(2):
		data.encode_u32(0,i)
		if archive.publish(path,archive.encode({"terrain":data})) != OK:
			quit(3)
			return
	print("WRITER_READY")
	var revision: int = 2
	while true:
		data.encode_u32(0,revision)
		if archive.publish(path,archive.encode({"terrain":data})) != OK:
			quit(4)
			return
		revision += 1
		await process_frame
