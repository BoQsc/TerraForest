# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://demo/structures.tscn").instantiate();root.add_child(game)
	for prop in game.props: prop.free()
	game.props.clear()
	var blank=ClassDB.instantiate("NativeBlockWorld")
	game.buildings.restore_snapshot(blank.capture_snapshot());blank.free()
	var cottage: Resource=load("res://addons/structures/prefabs/brick_cottage.tres")
	var frontage=ClassDB.instantiate("NativeBlockPrefab")
	var passed: bool=frontage.compose_frontage([cottage],2,8,3,1703) and game.buildings.place_prefab(frontage,Vector3i.ZERO,0,false)
	# Cottage doorway is local (0,1..2,+5). After aligning its bounds,
	# the north door lies at (4,2..3,-9), south at (4,2..3,+8).
	for x in [4,16]:
		for z in [-9,8]:
			passed=passed and game.buildings.get_cell(Vector3i(x,2,z))==0 and game.buildings.get_cell(Vector3i(x,3,z))==0
			passed=passed and game.buildings.get_cell(Vector3i(x-1,2,z))!=0 and game.buildings.get_cell(Vector3i(x+1,2,z))!=0
	game.camera.position=Vector3(40,30,45);game.camera.look_at(Vector3(10,3,0));game.buildings.set_focus(game.camera.position)
	game.notice="Four cottages · reserved street · no terrain grading"
	var deadline:=Time.get_ticks_msec()+15000
	while not game.buildings.is_idle() and Time.get_ticks_msec()<deadline: await process_frame
	passed=passed and game.buildings.is_idle() and game.buildings.stats().mesh_chunks>0
	game.set_process(false)
	game.label.text="Four cottages · entrances face reserved street\n1,872 cells · 8 mesh chunks · 4,768 triangles\nVisual check only · no FPS measurement\nTerrain grading and asphalt are not included"
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/frontage_overview.png")
	game.camera.position=Vector3(26,3,0);game.camera.look_at(Vector3(3,3,0))
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/frontage_street.png")
	print("FRONTAGE_RENDER ",{"passed":passed,"cells":frontage.get_cell_count(),"stats":game.buildings.stats(),"scope":"four cottage geometry/entrance check, not terrain integration or frame-rate measurement"})
	game.free();quit(0 if passed else 1)
