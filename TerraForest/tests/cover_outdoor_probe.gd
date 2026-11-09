# SPDX-License-Identifier: 0BSD
extends RefCounted

# Test-only repeatable camera motion. Production world services continue running;
# fly mode holds the sample height. This does not qualify walking collision.
func run(driver:SceneTree,game:Node,output:String)->Dictionary:
	var grounded:bool="--trace-grounded-walk" in OS.get_cmdline_user_args()
	var desired:Vector3=game.player.position+Vector3(24,0,24)
	var target:=Vector3.INF
	var best:=INF
	for key:Vector2i in game.ground_cover.resident:
		var grass:Dictionary=game.ground_cover.resident[key][2]
		var packed:PackedFloat32Array=grass.transforms
		for index:int in grass.ids.size():
			var point:=Vector3(packed[index*12+3],packed[index*12+7],packed[index*12+11])
			var score:=Vector2(point.x-desired.x,point.z-desired.z).length_squared()
			if score<best:best=score;target=point
	if not target.is_finite():return {"ok":false,"reason":"no resident grass target"}
	driver.label="outdoor_preparation"
	game.teleport(target+Vector3(0,0,4),target.y+.1)
	if not await driver.wait_for(func():return not game.loading_active and not game.waiting_spawn and not game.needs_floor_spawn,60):
		return {"ok":false,"reason":"outdoor arrival did not settle"}
	game.fly=not grounded;game._clear_motion();game.yaw=0;game.pitch=-.24
	# The normal Alt/tool-cursor path admits movement without capturing the
	# user's desktop pointer. The production motor, gravity and collisions run.
	var prior_mouse_access:bool=game.session_menu.developer_hud.mouse_access
	if grounded:game.session_menu.developer_hud.mouse_access=true
	game.player.rotation.y=0;game.camera.rotation.x=game.pitch
	await driver.wait_for(func():return false,5)
	var origin:Vector3=game.player.position
	var poses:Array=[]
	var grounded_frames:=0
	var movement_frames:=0
	for index:int in 3:
		if index>0:
			driver.label="outdoor_sweep"
			var began:=Time.get_ticks_msec()
			if grounded:game.controls.set_key(KEY_D,true,Time.get_ticks_usec())
			while Time.get_ticks_msec()-began<(1500 if grounded else 4000):
				game.app_focused=true
				if grounded:
					movement_frames+=1
					if game.player.is_on_floor():grounded_frames+=1
				else:
					var distance:float=8.0*(index-1)+8.0*minf(1.0,(Time.get_ticks_msec()-began)/4000.0)
					game.player.position=origin+Vector3(distance,0,0);game.player.velocity=Vector3.ZERO
				await driver.process_frame
			if grounded:game.controls.set_key(KEY_D,false,Time.get_ticks_usec())
		if not grounded:game.player.position=origin+Vector3(index*8,0,0)
		driver.label="outdoor_view_"+str(index)
		await driver.wait_for(func():return false,4)
		poses.append({"player":game.player.position,"camera":game.camera.global_transform})
		# Screenshot readback is deliberately outside the timing phase.
		driver.label="test_screenshot"
		await RenderingServer.frame_post_draw
		var readback_started:=Time.get_ticks_usec()
		driver.root.get_texture().get_image().save_png(output.path_join("outdoor_"+str(index)+".png"))
		poses[-1].screenshot_us=Time.get_ticks_usec()-readback_started
		# The next interval includes this synchronous readback. Drain it while
		# still labelled screenshot, before entering another gameplay phase.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	game.session_menu.developer_hud.mouse_access=prior_mouse_access
	var travelled:float=Vector2(game.player.position.x-origin.x,game.player.position.z-origin.z).length()
	return {"ok":not grounded or (travelled>4.0 and grounded_frames>movement_frames*.8 and not game.player_life.dead),"target":target,"poses":poses,"grounded":grounded,"travelled":travelled,"grounded_frames":grounded_frames,"movement_frames":movement_frames,"scope":"Production motor walking with gravity and collisions through the existing tool-cursor input gate; no density or quality overrides" if grounded else "16 m camera sweep through production cover; fly mode holds height, no density or quality overrides; not a walking/collision qualification"}
