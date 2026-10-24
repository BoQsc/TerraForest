# SPDX-License-Identifier: 0BSD
extends SceneTree
const LIBRARY = preload("res://addons/characters/runtime/assets/Human.unarmed.res")
const FOLDER = "res://reports/unarmed"
func _initialize() -> void: run.call_deferred()
func panel(kind: String) -> Dictionary:
	var viewport := SubViewport.new(); viewport.size = Vector2i(1280,720); viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var stage := Node3D.new(); viewport.add_child(stage)
	var world := WorldEnvironment.new(); world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR; world.environment.background_color = Color("30383e")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE; world.environment.ambient_light_energy = .75; stage.add_child(world)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-45,-35,0); light.light_energy = 1.6; stage.add_child(light)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-25,135,0); fill.light_energy = .55; stage.add_child(fill)
	var floor_view := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(30,30); floor_view.mesh = plane
	var material := StandardMaterial3D.new(); material.albedo_color = Color("566168"); material.roughness = .88
	floor_view.material_override = material; stage.add_child(floor_view)
	var camera := Camera3D.new(); camera.fov = 75; camera.near = .035; camera.position = Vector3(0,1.65,0); camera.current = true; stage.add_child(camera)
	var tools_view = preload("res://addons/player_runtime/tool_view.gd").new(); camera.add_child(tools_view)
	tools_view.equip(0); tools_view.set_process(false)
	var view = tools_view.human; view.set_process(false)
	if not view.clips.has("FP_Unarmed_Idle"):
		view.animation_player.add_animation_library("unarmed_review",LIBRARY)
		for clip in LIBRARY.get_animation_list(): view.clips[String(clip)] = "unarmed_review/" + String(clip)
	if kind != "first_person":
		tools_view.reparent(stage); tools_view.transform = Transform3D.IDENTITY
		view.position = Vector3(0,0,.03); view.rotation = Vector3(0,PI,0); view.set_third_person(true)
		camera.position = Vector3(2.0,1.65,-1.55) if kind == "body" else Vector3(.72,1.72,-.92)
		camera.fov = 50 if kind == "body" else 38
		camera.look_at(Vector3(0,1.15,-.20) if kind == "body" else Vector3(.16,1.40,-.39))
		if kind == "front":
			camera.position = Vector3(.105,1.52,-1.10); camera.fov = 25
			camera.look_at(Vector3(.105,1.52,-.47))
	var title := Label.new(); title.position = Vector2(28,22); title.text = "EMPTY HANDS / " + kind.replace("_"," ").to_upper()
	title.add_theme_font_size_override("font_size",24); viewport.add_child(title)
	return {"viewport":viewport,"view":view}
func pose(view: Node, time: float) -> void:
	view.animation_player.play(view.clips["FP_Unarmed_Punch"],0)
	view.animation_player.seek(time,true); view.animation_player.pause(); view.animation_player.advance(0)
func run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var panels := {"first_person":panel("first_person"),"body":panel("body"),"detail":panel("detail"),"front":panel("front")}
	var video := "--video" in OS.get_cmdline_user_args()
	var snapshots := {0:"neutral",8:"closed",12:"loaded",20:"extension",28:"contact",36:"recoil",50:"relax",68:"neutral_again"}
	if video: DirAccess.make_dir_recursive_absolute(FOLDER + "/frames")
	for frame: int in range(240) if video else snapshots.keys():
		var cursor: float = frame/60.0
		if video:
			var t := frame/30.0
			cursor = clampf(t-.7,0,68.0/60) if t < 2.6 else (clampf(t-3,0,68.0/60) if t < 4.8 else clampf((t-5.1)*.5,0,68.0/60))
		for data: Dictionary in panels.values(): pose(data.view,cursor)
		await process_frame; RenderingServer.force_draw(false); RenderingServer.force_draw(false)
		if video: panels.first_person.viewport.get_texture().get_image().save_png(FOLDER + "/frames/%03d.png" % frame)
		else:
			for kind: String in panels: panels[kind].viewport.get_texture().get_image().save_png(FOLDER + "/" + kind + "_" + snapshots[frame] + ".png")
	for data: Dictionary in panels.values(): data.viewport.free()
	print("UNARMED_PREVIEW complete video=",video); quit()
