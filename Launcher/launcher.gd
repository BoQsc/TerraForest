# SPDX-License-Identifier: 0BSD
extends Control
# This separate, asset-free Godot project can start even when the game needs imports.
var project_root := ProjectSettings.globalize_path("res://").path_join("../TerraForest").simplify_path()
var engine := OS.get_executable_path()
var continue_last := "--continue-last" in OS.get_cmdline_user_args()
var prepare_only := "--prepare-only" in OS.get_cmdline_user_args()
var worker: Thread
var phase := ""
var game_pid := -1
var lock := TCPServer.new()
var status: Label
var details: Label
var retry: Button
var log_path := ""
var closing_requested := false

func _ready() -> void:
 Engine.max_fps = 60
 get_tree().auto_accept_quit = false
 var panel := MarginContainer.new()
 panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for side in ["left", "top", "right", "bottom"]:panel.add_theme_constant_override("margin_" + side, 28)
 add_child(panel)
 var column := VBoxContainer.new();column.add_theme_constant_override("separation", 18);panel.add_child(column)
 var title := Label.new();title.text = "TerraForest";title.add_theme_font_size_override("font_size", 30);column.add_child(title)
 status = Label.new();status.text = "Preparing your game…";column.add_child(status)
 details = Label.new();details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;details.size_flags_vertical = Control.SIZE_EXPAND_FILL;column.add_child(details)
 var actions := HBoxContainer.new();column.add_child(actions)
 retry = Button.new();retry.text = "Retry";retry.hide();retry.pressed.connect(start);actions.add_child(retry)
 var logs := Button.new();logs.text = "Open logs";logs.pressed.connect(func():OS.shell_open(project_root.path_join("reports")));actions.add_child(logs)
 var close := Button.new();close.text = "Close";close.pressed.connect(close_requested);actions.add_child(close)
 # Keep one preparation/game launch per checkout. No platform-specific shell.
 var port := 32000 + posmod(project_root.hash(), 16000)
 if lock.listen(port, "127.0.0.1") != OK:
  fail("TerraForest is already launching or running from this launcher.");return
 # Present the working controls before filesystem checks or process startup.
 if DisplayServer.get_name() != "headless":await RenderingServer.frame_post_draw
 else:await get_tree().process_frame
 if not closing_requested:start()

func start() -> void:
 if worker != null or game_pid > 0:return
 retry.hide()
 if not FileAccess.file_exists(project_root.path_join("project.godot")):
  fail("The TerraForest source project must be beside the Launcher folder.");return
 DirAccess.make_dir_recursive_absolute(project_root.path_join("reports"))
 if OS.get_name() == "Windows":
  phase = "check";status.text = "Opening TerraForest…"
  details.text = "Checking whether source preparation is needed."
  worker = Thread.new()
  if worker.start(preparation_cache.bind("check")) != OK:worker = null;fail("Cannot check source preparation.")
 else:
  start_native()

func start_native() -> void:
 if OS.get_name() == "Windows":
  phase = "native"
  status.text = "Checking native code…"
  details.text = "Changed C++ extensions are rebuilt before the game starts."
  log_path = project_root.path_join("reports/worlds_native.log")
  worker = Thread.new()
  if worker.start(prepare_native) != OK:worker = null;fail("Cannot start the native code check.")
 else:
  start_import()

func preparation_cache(action: String) -> int:
 var args := PackedStringArray([project_root.path_join("tools/source_launch_cache.py"), action, "--engine", engine])
 if action == "check" and "--force-prepare" in OS.get_cmdline_user_args():args.append("--force")
 var output:Array=[]
 var result := OS.execute("py.exe", PackedStringArray(["-3"]) + args, output, true, false)
 if result == -1:
  output.clear();result = OS.execute("python.exe", args, output, true, false)
 if not output.is_empty():print("\n".join(output).right(16000))
 return result

func prepare_native() -> int:
 var script := project_root.path_join("tools/prepare_launcher_native.py")
 var result := OS.execute("py.exe", PackedStringArray(["-3", script]), [], false, false)
 if result == -1:
  result = OS.execute("python.exe", PackedStringArray([script]), [], false, false)
 return result

func start_import() -> void:
 phase = "import"
 status.text = "Refreshing changed resources…"
 details.text = "Godot prepares scripts and assets in the background. No editor window is opened."
 log_path = project_root.path_join("reports/worlds_import.log")
 # Fresh log: never mistake a previous launch's errors for this import.
 var file := FileAccess.open(log_path, FileAccess.WRITE)
 if file == null:fail("Cannot write the import log.");return
 file.close()
 worker = Thread.new()
 var args := PackedStringArray(["--headless", "--editor", "--path", project_root, "--log-file", log_path, "--import"])
 if worker.start(run_process.bind(args)) != OK:worker = null;fail("Cannot start resource preparation.")

func run_process(arguments: PackedStringArray) -> int:
 # Joining this worker establishes ownership of the process result.
 var code := OS.execute(engine, arguments, [], false, false)
 if code != 0:return code
 # Import logs can be large. Validate them before joining, away from input.
 var log_text := FileAccess.get_file_as_string(log_path)
 if "SCRIPT ERROR:" in log_text or "Failed to load script" in log_text or "Failed to load GDExtension" in log_text:return ERR_PARSE_ERROR
 return OK

func _process(_delta: float) -> void:
 if game_pid > 0:
  if not OS.is_process_running(game_pid):
   var code := OS.get_process_exit_code(game_pid)
   game_pid = -1
   if code == 0:get_tree().quit()
   else:
    get_window().mode = Window.MODE_WINDOWED
    fail("TerraForest stopped unexpectedly (exit %d). See worlds_game.log in Open logs." % code)
  return
 if worker == null or worker.is_alive():return
 var exit_code: int = worker.wait_to_finish();worker = null
 if closing_requested:finish_close();return
 if phase == "check":
  if exit_code == 0:launch_game();return
  if exit_code == 2:start_native();return
  fail("Cannot validate source preparation. See the launcher log.");return
 if phase == "identity":
  if exit_code != OK:fail("Cannot record the prepared game identity.");return
  launch_game();return
 if phase == "native":
  if exit_code != 0:
   fail("Native code preparation failed (exit %d). See worlds_native.log in Open logs. Windows native preparation requires Python and Git." % exit_code)
   return
  start_import()
  return
 if exit_code != 0:
  fail("Resource preparation failed (code %d). See %s" % [exit_code, log_path]);return
 if phase == "import":
  phase = "icons";status.text = "Preparing item previews…"
  log_path = project_root.path_join("reports/worlds_icons.log")
  worker = Thread.new()
  if worker.start(run_process.bind(PackedStringArray(["--headless", "--path", project_root, "--log-file", log_path, "--script", "res://tools/ensure_item_icons.gd"]))) != OK:
   worker = null;fail("Cannot prepare item previews.")
  return
 phase = "identity";status.text = "Opening TerraForest…"
 worker = Thread.new()
 if worker.start(record_identity) != OK:worker = null;fail("Cannot record the prepared game identity.")

func record_identity() -> int:
 # Executable/library hashing is IO work, never an input-thread operation.
 var identity := {"mode": "source", "project": project_root, "engine": engine, "engine_sha256": FileAccess.get_sha256(engine), "continue_last": continue_last, "prepared_at": Time.get_datetime_string_from_system(true), "water_script_sha256": FileAccess.get_sha256(project_root.path_join("addons/volumetric_water/lake_world.gd")), "generation_script_sha256": FileAccess.get_sha256(project_root.path_join("addons/world_runtime/generate_world_task.gd"))}
 var water_libraries := {}
 var water_bin := project_root.path_join("addons/volumetric_water/bin")
 for filename in DirAccess.get_files_at(water_bin):
  if filename.ends_with(".dll") or filename.ends_with(".so") or filename.ends_with(".dylib"):
   water_libraries[filename] = FileAccess.get_sha256(water_bin.path_join(filename))
 identity["water_native_sha256"] = water_libraries
 var file := FileAccess.open(project_root.path_join("reports/worlds_launch.json"), FileAccess.WRITE)
 if file == null:return FileAccess.get_open_error()
 file.store_string(JSON.stringify(identity, "  "))
 file.close()
 if OS.get_name() == "Windows":return preparation_cache("record")
 return OK

func launch_game() -> void:
 if prepare_only:get_tree().quit();return
 var args := PackedStringArray(["--path", project_root, "--log-file", project_root.path_join("reports/worlds_game.log"), "--max-fps", "60", "res://demo/worlds.tscn", "--"])
 if continue_last:args.append("--continue-last")
 if DisplayServer.get_name()=="headless":args.insert(0,"--headless")
 game_pid = OS.create_process(engine, args)
 if game_pid <= 0:fail("Godot could not start TerraForest.");return
 status.text = "TerraForest is running"
 get_window().mode = Window.MODE_MINIMIZED

func fail(message: String) -> void:
 status.text = "Unable to launch TerraForest"
 details.text = message
 retry.visible = lock.is_listening()
 push_error(message)
 if prepare_only:get_tree().quit(1)

func close_requested() -> void:
 closing_requested = true
 if worker != null:
  # A build/import owns files until it exits. Minimize immediately, then
  # release the lease without launching another phase or opening the game.
  get_window().mode = Window.MODE_MINIMIZED
  return
 finish_close()

func finish_close() -> void:
 get_tree().quit()

func _notification(what: int) -> void:
 if what == NOTIFICATION_WM_CLOSE_REQUEST:close_requested()
