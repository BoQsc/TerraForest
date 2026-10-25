extends SceneTree

const Recipes=preload("res://reviews/modular_buildings/recipes.gd")
var checks:=0
var failures:=0
var viewer: Node3D
var output:="res://reports/modular_building_review"

func _initialize() -> void: run.call_deferred()

func check(accepted: bool, label: String) -> void:
	checks+=1
	if not accepted:failures+=1
	print("PASS " if accepted else "FAIL ",label)

func picture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"capture "+name)

func press(text: String) -> void:
	for control in viewer.find_children("*","Button",true,false):
		if control.text==text:
			control.pressed.emit()
			return
	check(false,"missing review control "+text)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):output=argument.trim_prefix("--review-output=")
	DirAccess.make_dir_recursive_absolute(output)
	viewer=preload("res://reviews/modular_buildings/viewer.gd").new();root.add_child(viewer)
	check(viewer.ready_ok,"four complete native prefabs and attached models publish atomically")
	if not viewer.ready_ok:
		print(viewer.placement_results);viewer.free();quit(1);return
	var blocks: Node3D=viewer.structures.blocks
	if "--restore-review" in OS.get_cmdline_user_args():
		var stored:=FileAccess.get_file_as_bytes(output.path_join("review.tfbs"))
		viewer.toggle_block()
		check(viewer.structures.restore_storage_snapshot(stored),"fresh process restores saved building/model data after a local edit")
		check(viewer.structures.capture_storage_snapshot()==stored,"fresh process preserves exact compound storage bytes")
		viewer.free();await process_frame
		print("MODULAR_BUILDING_RESTORE checks=",checks," failures=",failures)
		quit(1 if failures else 0);return
	var originals: Array[Resource]=[Recipes.Furniture.enclosed_cottage(),Recipes.Workshop.village_shop()]
	press("VILLAGE SHOP B");press("Interior")
	check(viewer.current_design==1 and viewer.current_view==1,"visible shop/interior buttons select the correct comparison")
	press("COTTAGE A");press("Detail")
	check(viewer.current_design==0 and viewer.current_view==2,"visible cottage/detail buttons select the correct comparison")
	press("Remove ONE arch block")
	check(viewer.removed,"visible removal button removes the candidate block")
	press("Exterior")
	check(not viewer.removed and viewer.current_view==0,"changing view restores demonstration edits")
	press("Play guided tour")
	check(viewer.current_design==0 and viewer.current_view==0 and viewer.tour_button.text.begins_with("Tour running"),"guided tour starts on cottage comparison")
	press("Interior")
	check(viewer.current_view==1 and viewer.tour_button.text=="Play guided tour","manual selection cancels the guided tour")
	for index in 2:
		var design: Dictionary=viewer.designs[index]
		check(originals[index].get_records()==design.original.get_records(),"production original unchanged "+design.title)
		check(design.original.get_model_attachments()==design.candidate.get_model_attachments(),"working doors, windows, furniture and storage retained "+design.title)
		check(design.candidate.get_meta("review_only",false),"candidate explicitly marked unapproved review-only")
		var authored: Resource=Recipes.cottage(blocks) if index==0 else Recipes.shop(blocks)
		check(authored.get_records()==design.candidate.get_records() and authored.get_model_attachments()==design.candidate.get_model_attachments(),"baked review matches its reproducible authoring recipe")
		var counts: Dictionary={}
		for word in Recipes.cells_of(design.candidate).values():
			var decoded: Dictionary=blocks.decode_block(word)
			counts[decoded.shape]=counts.get(decoded.shape,0)+1
		check(counts.get(11,0)==2 and counts.get(9,0)>10 and counts.get(12,0)>0,"real building uses separate arch, panel and ridge blocks")
		var loaded: Resource
		print("BUILDING_COUNTS ",design.title," ",counts)
		check(ResourceSaver.save(design.candidate,output.path_join("cottage_a.tres" if index==0 else "shop_b.tres"))==OK,"bake native prefab review asset")
		loaded=load(output.path_join("cottage_a.tres" if index==0 else "shop_b.tres"))
		check(loaded.get_records()==design.candidate.get_records() and loaded.get_model_attachments()==design.candidate.get_model_attachments(),"baked review prefab preserves every block and attached object")
		viewer.select_view(index,0);await picture("cottage_exterior" if index==0 else "shop_exterior")
		viewer.select_view(index,1);await picture("cottage_interior" if index==0 else "shop_interior")
		viewer.select_view(index,2);await picture("cottage_detail" if index==0 else "shop_detail")
		var before: PackedByteArray=blocks.capture_snapshot()
		var cells_before: int=blocks.stats().cells
		viewer.toggle_block();blocks.flush_bakes()
		check(blocks.stats().cells==cells_before-1,"demonstration removes exactly one arch block "+design.title)
		await picture("cottage_removed" if index==0 else "shop_removed")
		viewer.toggle_block();blocks.flush_bakes()
		check(blocks.capture_snapshot()==before,"restoring that cell restores exact building bytes")
		var origin:=Vector3(design.base)+Vector3(viewer.PAIR_OFFSET,0,0)
		var supported:=true
		if index==0:
			for horizontal in [-.94,1.94]:
				for depth in [7.1,7.5,7.9]:
					var occupied: PackedByteArray=blocks.sample_solid(PackedVector3Array([origin+Vector3(horizontal,.99,depth),origin+Vector3(horizontal,1.01,depth)]))
					supported=supported and occupied==PackedByteArray([1,1])
			for column in [-1,1]:supported=supported and blocks.get_cell(Vector3i(origin)+Vector3i(column,0,7))==65
			check(supported,"both porch uprights have continuous level pedestal support")
	var saved: PackedByteArray=viewer.structures.capture_storage_snapshot()
	check(not saved.is_empty() and viewer.structures.restore_storage_snapshot(saved),"combined block/model storage roundtrip")
	FileAccess.open(output.path_join("review.tfbs"),FileAccess.WRITE).store_buffer(saved)
	viewer.toggle_doors()
	for frame in 8:await physics_frame
	var collection: Node3D=viewer.structures.model(preload("res://addons/structures/door_catalog.gd").KEY)
	for identity in collection.get_ids():check(viewer.hinges.is_open(identity),"retained entrance door opens")
	await walk_designs()
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"stats":blocks.stats(),"scope":"isolated architecture comparison and native player traversal; not terrain or settlement approval"},"  "))
	viewer.free();await process_frame
	print("MODULAR_BUILDING_REVIEW checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func walk_designs() -> void:
	var player:=CharacterBody3D.new();player.collision_mask=7;player.collision_layer=8
	player.floor_snap_length=.35;player.floor_max_angle=deg_to_rad(48);player.floor_constant_speed=true;player.safe_margin=.01
	var shape:=CapsuleShape3D.new();shape.radius=.34;shape.height=1.8
	var collider:=CollisionShape3D.new();collider.shape=shape;collider.position.y=.9;player.add_child(collider);root.add_child(player)
	var motor: RefCounted=ClassDB.instantiate("NativePlayerMovement")
	for design: Dictionary in viewer.designs:
		for side in 2:
			var origin:=Vector3(design.base)+Vector3(side*viewer.PAIR_OFFSET,0,0)
			viewer.structures.set_model_focus(origin+Vector3(.5,2,0))
			player.position=origin+Vector3(.5,.03,design.approach);player.velocity=Vector3.ZERO
			for frame in 8:await physics_frame
			var reached:=false
			for tick in 480:
				await physics_frame
				player.velocity=motor.walking_velocity(Vector3.FORWARD,player.velocity,1.0/60,false,player.is_on_floor(),false)
				motor.move_grounded(player,1.0/60)
				if player.position.z<origin.z-3 and player.is_on_floor():reached=true;break
			check(reached and absf(player.position.y-origin.y-design.floor)<.1,"native player walks steps, door and interior aisle "+design.title+" side "+str(side))
			print("WALK_END ",design.title," side=",side," position=",player.position-origin)
			var returned:=false
			for tick in 480:
				await physics_frame
				player.velocity=motor.walking_velocity(Vector3.BACK,player.velocity,1.0/60,false,player.is_on_floor(),false)
				motor.move_grounded(player,1.0/60)
				if player.position.z>origin.z+design.approach and player.is_on_floor():returned=true;break
			check(returned and absf(player.position.y-origin.y)<.1,"native player exits and descends to approach "+design.title+" side "+str(side))
	player.free()
