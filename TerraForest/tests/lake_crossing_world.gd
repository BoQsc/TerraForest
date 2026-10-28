extends "res://tests/approved_city_world.gd"

const Crossings=preload("res://addons/structures/lake_crossings.gd")
var destroyed:=Vector3i(-1,-1,-1)
var inspected:=false
var bridge_plan:Dictionary={}
var snapshot_mode:=false

func run()->void:
 var snapshot:=""
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--lake-snapshot="):snapshot=argument.trim_prefix("--lake-snapshot=")
 if snapshot.is_empty():await super.run();return
 if not check(snapshot.begins_with("recipe_generated_") and snapshot.is_valid_filename(),"inspection restricted to disposable generated check slot"):await finish();return
 snapshot_mode=true;folder="res://reports/lake_crossing_world"
 var path:="user://worlds/"+snapshot+".trw"
 var before:=FileAccess.get_sha256(path)
 Options.set_arguments(PackedStringArray(["--world-slot="+snapshot,"--snapshot-readonly","--gameplay-construction","--actors","--vehicle-fleet"]),true)
 change_scene_to_file("res://demo/world.tscn");await scene_changed
 if check(await wait_for(game_ready,90),"separate process restores generated lake world"):await verify_approved_records(current_scene)
 check(before==FileAccess.get_sha256(path),"read-only traversal preserves saved world bytes")
 FileAccess.open(folder.path_join("reopen.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"checks":checks,"slot":snapshot,"fresh_process_reopen":true},"  "))
 await finish()

func verify_approved_records(game:Node)->void:
 if bridge_plan.is_empty():
  var options:Dictionary=Recipe.codec().decode(game.world_recipe.store.capture_snapshot())
  var worker:=Thread.new();worker.start(Plan.build.bind(1703,29,true,true,"user://lake_review_plan",options))
  while worker.is_alive():await process_frame
  bridge_plan=worker.wait_to_finish()
 if not check(bridge_plan.get("ok",false) and not bridge_plan.get("bridges",[]).is_empty(),"real generated landscape includes connected lake bridge"):return
 game.background_fps=60;game.session_menu.set_open(false)
 for crossing:Dictionary in bridge_plan.bridges:
  game.teleport(crossing.banks[0]+Vector3.UP)
  var asset:=Crossings.asset(crossing)
  var bounds:AABB=asset.placement_bounds(crossing.origin,crossing.rotation)
  if not check(await wait_for(func():return not game.loading_active and game.world_vehicle.ready_bounds(game,bounds.grow(5)),90),"bridge terrain, blocks, water and vegetation ready"):return
  var transformed:Resource=ClassDB.instantiate("NativeBlockPrefab")
  check(transformed.compose([asset],PackedInt32Array([0,crossing.origin.x,crossing.origin.y,crossing.origin.z,crossing.rotation])),"native bridge transform composes")
  var records:PackedInt32Array=transformed.get_records();var exact:=true
  if snapshot_mode:destroyed=Vector3i((crossing.banks[0]+crossing.banks[1])*.5)-Vector3i(0,1,0)
  for offset in range(0,records.size(),4):
   var cell:=Vector3i(records[offset],records[offset+1],records[offset+2])
   exact=exact and game.structures.blocks.get_cell(cell)==(0 if cell==destroyed else records[offset+3])
  check(exact,"every generated bridge cell matches before and after save/reload")
  if snapshot_mode:game.structures.blocks.set_cells(PackedInt32Array([destroyed.x,destroyed.y,destroyed.z,160]));await physics_frame
  if inspected:continue
  game.set_physics_process(false);game._clear_motion();game.fly=true
  var camera_pose:Transform3D=game.camera.transform
  var body:=CharacterBody3D.new();body.collision_layer=8;body.collision_mask=7;body.floor_snap_length=.35;body.safe_margin=.004;body.floor_max_angle=deg_to_rad(48)
  var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8
  var shape:=CollisionShape3D.new();shape.shape=capsule;shape.position.y=.9;body.add_child(shape);game.add_child(body)
  var motor:RefCounted=ClassDB.instantiate("NativePlayerMovement")
  var direction:Vector3=(crossing.banks[1]-crossing.banks[0]).normalized()
  var side:=Vector3(-direction.z,0,direction.x)
  var start:Vector3=crossing.banks[0]-direction*2+Vector3.UP*.04
  var finish:Vector3=crossing.banks[1]+direction*2+Vector3.UP*.04
  game.player.position=start+side*8
  var start_hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start+Vector3.UP,start-Vector3.UP*2,7,[game.player.get_rid(),body.get_rid()]))
  var finish_hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(finish+Vector3.UP,finish-Vector3.UP*2,7,[game.player.get_rid(),body.get_rid()]))
  if not check(not start_hit.is_empty() and not finish_hit.is_empty(),"bridge route endpoints have actual collision support"):body.free();return
  start=start_hit.position+Vector3.UP*.04;finish=finish_hit.position+Vector3.UP*.04
  for bank:Vector3 in crossing.banks:
   var joined:=true
   for sample in range(-10,11):
    var point:Vector3=bank+direction*sample*.05
    var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP*2,7,[game.player.get_rid(),body.get_rid()])
    var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(query)
    joined=joined and not hit.is_empty() and absf(float(hit.get("position",Vector3.ZERO).y)-bank.y)<.18 and float(hit.get("normal",Vector3.ZERO).y)>.85
   check(joined,"bridge entrance centreline joins the terrain without a sharp dip")
  await walk_route(game,body,motor,start,finish,"lake bridge",false)
  await walk_route(game,body,motor,finish,start,"lake bridge return",false)
  await walk_route(game,body,motor,start,finish,"lake bridge",true,2400)
  await walk_route(game,body,motor,finish,start,"lake bridge return",true,2400)
  body.free()
  game.set_process(false);game.tool_view.hide()
  var center:Vector3=(crossing.banks[0]+crossing.banks[1])*.5
  game.camera.global_position=center+side*32+Vector3.UP*15+direction*12;game.camera.look_at(center)
  for frame in 90:await process_frame
  await photograph("bridge_overview")
  game.camera.global_position=start+Vector3.UP*1.7;game.camera.look_at(finish+Vector3.UP*1.2)
  for frame in 60:await process_frame
  await photograph("bridge_deck")
  game.camera.global_position=center+side*16+Vector3(0,-1,0);game.camera.look_at(center-Vector3.UP)
  for frame in 60:await process_frame
  await photograph("bridge_water_clearance")
  var durations:=PackedFloat64Array();var previous:=Time.get_ticks_usec()
  for frame in 180:
   await process_frame
   var now:=Time.get_ticks_usec();durations.append((now-previous)/1000.0);previous=now
  durations.sort()
  metrics.append({"span":crossing.span,"bridge_blocks":asset.get_cell_count(),"p95_ms":durations[171],"worst_ms":durations[-1],"gpu":RenderingServer.get_video_adapter_name()})
  game.camera.global_position=center-side*80+Vector3.UP*150;game.camera.look_at(center+side*70)
  for frame in 90:await process_frame
  await photograph("lake_overview")
  destroyed=Vector3i(center)-Vector3i(0,1,0)
  check(game.structures.blocks.get_cell(destroyed)!=0 and game.structures.blocks.set_cells(PackedInt32Array([destroyed.x,destroyed.y,destroyed.z,0])),"one deck block can be removed independently")
  game.camera.transform=camera_pose;game.tool_view.show();game.set_process(true);game.set_physics_process(true)
 inspected=true
 FileAccess.open(folder.path_join("bridges.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"metrics":metrics,"bridges":bridge_plan.bridges,"destroyed_cell":destroyed,"routes_exercised":"--city-metrics-only" not in OS.get_cmdline_user_args(),"scope":"One populated seed-1703 world; routes only when routes_exercised=true; one independently removable block; 180 stationary rendered frames excluding screenshots. Fresh-process mode is read-only."},"  "))
