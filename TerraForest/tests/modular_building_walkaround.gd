extends SceneTree

var review: Node3D
var checks := 0
var failures := 0
var output := "res://reports/modular_building_walkaround"

func _initialize() -> void:run.call_deferred()

func check(accepted: bool, label: String) -> void:
	checks+=1
	if not accepted:failures+=1
	print("PASS " if accepted else "FAIL ",label)

func key(code: int) -> void:
	if not review.focused:
		print("REVIEW_INPUT restoring simulated focus before key ",code)
		review._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=true
	Input.parse_input_event(event);await process_frame
	event=InputEventKey.new();event.physical_keycode=code;event.pressed=false
	Input.parse_input_event(event);await process_frame

func photograph(name: String, position_value: Vector3, look: Vector3) -> void:
	if DisplayServer.get_name()=="headless":return
	review.set_pose(position_value,look)
	for frame in 20:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"retain scene image "+name)

func walk_to(target: Vector3, label: String) -> bool:
	var arrived:=false
	for tick in 720:
		await physics_frame
		var direction: Vector3=target-review.player.position;direction.y=0
		review.walk_step(direction.normalized() if direction.length()>.16 else Vector3.ZERO,1.0/60)
		if direction.length()<.2 and review.player.is_on_floor():arrived=true;break
	check(arrived,label)
	if not arrived:print("WALK_BLOCKED at=",review.player.position," wanted=",target)
	return arrived

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):output=argument.trim_prefix("--review-output=")
	DirAccess.make_dir_recursive_absolute(output)
	review=load("res://reviews/modular_buildings/walkaround.tscn").instantiate();root.add_child(review)
	review.set_physics_process(false)
	check(review.ready_ok and review.signs_ready,"walk-around scene loads originals and approved addition, native paths and signs")
	if not review.ready_ok or not review.signs_ready:
		print(review.placement_results);review.free();quit(1);return
	var blocks: Node3D=review.structures.blocks
	check(review.placards.size()==3,"three explicit A0 B0 B1 placards")
	check(not review.include_building({"decision":"pending"},1),"unreviewed additions are excluded unless explicitly approved")
	check(review.placement_results.size()==3 and blocks.get_cell(Vector3i(13,0,0))==0,"rejected A1 is not placed in the active review")
	check(review.current_design==1 and review.player.position.z== -15,"review starts at approved shop comparison")
	var identities:Array[String]=[]
	for sign: Dictionary in review.placards:
		identities.append(sign.id)
		var design: Dictionary=review.designs[sign.design]
		var asset: Resource=design.original if sign.side==0 else design.candidate
		var exact:=true
		var records: PackedInt32Array=asset.get_records()
		for offset in range(0,records.size(),4):
			var cell: Vector3i=sign.origin+Vector3i(records[offset],records[offset+1],records[offset+2])
			if blocks.get_cell(cell)!=records[offset+3]:exact=false;break
		check(exact,"building matches unchanged original/approved-R1 resource "+sign.id)
		check(sign.status==("ORIGINAL / UNCHANGED" if sign.side==0 else "APPROVED / ADDITION ONLY"),"sign states correct approval status "+sign.id)
		check(blocks.get_cell(sign.cell+Vector3i(-2,0,0))==37 and blocks.get_cell(sign.cell+Vector3i(0,2,0))==blocks.encode_block(9,12,3),"sign built from separate post/panel cells "+sign.id)
	check(identities==["A0","B0","B1"],"stable identities exclude the rejected cottage")
	check(blocks.get_cell(Vector3i(0,-1,-10))==192 and blocks.get_cell(Vector3i(12,-1,14))==192,"connected paths use the trusted top-plate grid cells")
	await key(KEY_2)
	check(review.player.position.z== -15 and not review.fly,"2 switches to shop row on foot")
	await key(KEY_3)
	check(review.fly and review.player.collision_mask==0,"3 opens whole-scene flight overview")
	await key(KEY_F)
	check(not review.fly and review.player.collision_mask==7 and review.player.position.z== -15,"F safely returns to the last grounded review position")
	await key(KEY_ESCAPE)
	check(review.paused and review.pause_panel.visible and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Esc releases mouse and opens review navigation")
	await key(KEY_ESCAPE)
	check(not review.paused and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"Esc resumes without an invisible input blocker")
	review._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not review.focused and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"focus loss clears movement and releases pointer")
	review._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	check(review.focused and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"focus return resumes captured controls when not paused")
	await photograph("cottage_row",Vector3(.5,7,32),Vector3(.5,4,0))
	await photograph("shop_row",Vector3(.5,8,-5),Vector3(.5,4,-38))
	review.overview()
	await photograph("overview",Vector3(39,29,43),Vector3(0,2,-14))
	review.select_view(0,0)
	await photograph("cottage_sign",Vector3(-3,2,18),Vector3(-12,3,2))
	await photograph("shop_sign",Vector3(3,2,-17),Vector3(12,3,-34))
	review.select_view(1,0)
	for frame in 15:await physics_frame
	await photograph("arrival",review.player.position,Vector3(.5,4,-38))
	await key(KEY_1)
	check(review.current_design==0 and review.player.position.z==21,"1 returns to retained original cottage")
	for sign: Dictionary in review.placards:
		var origin:=Vector3(sign.origin)
		var plaza: float=14 if sign.design==0 else -22
		if not await walk_to(Vector3(.5,0,plaza),"walk central path to "+sign.id):break
		if not await walk_to(Vector3(origin.x+.5,0,plaza),"walk connected frontage to "+sign.id):break
		var outside:=origin+Vector3(.5,0,6.8 if sign.design==0 else 9.8)
		if not await walk_to(outside,"climb approach toward closed door "+sign.id):break
		review.structures.set_model_focus(review.player.position)
		for frame in 15:await physics_frame
		var door_center:=origin+Vector3(.5,3 if sign.design==0 else 2,5.5 if sign.design==0 else 8.5)
		review.set_pose(review.player.position,door_center)
		var target: Dictionary=review.door_target()
		check(not target.is_empty(),"normal 3m E ray targets retained door "+sign.id)
		if target.is_empty():break
		await key(KEY_E)
		check(review.hinges.is_open(target.id),"E opens this door without toggling other buildings "+sign.id)
		for frame in 12:await physics_frame
		if not await walk_to(origin+Vector3(.5,0,-3),"walk inside through doorway and aisle "+sign.id):break
		check(absf(review.player.position.y-origin.y-(2 if sign.design==0 else 1))<.1,"solid supported interior floor "+sign.id)
		if sign.side==1:
			await photograph("interior_"+sign.id,review.player.position,origin+Vector3(2,2 if sign.design==1 else 3,-1))
		if not await walk_to(Vector3(origin.x+.5,0,plaza),"exit house and descend to connected path "+sign.id):break
		if not await walk_to(Vector3(.5,0,plaza),"return to central review path "+sign.id):break
	check(review.player.position.z< -20,"complete circuit reaches and leaves both shop versions")
	var snapshot: PackedByteArray=review.structures.capture_storage_snapshot()
	check(not snapshot.is_empty() and review.structures.restore_storage_snapshot(snapshot),"scene structures retain compound storage roundtrip")
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"stats":blocks.stats(),"scope":"isolated signed review scene, real native walking and door interaction; no generated terrain or NPC acceptance"},"  "))
	review.free();await process_frame
	print("MODULAR_BUILDING_WALKAROUND checks=",checks," failures=",failures)
	quit(1 if failures else 0)
