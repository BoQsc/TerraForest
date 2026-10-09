# SPDX-License-Identifier: 0BSD
extends SceneTree
const Presentation=preload("res://addons/presentation/fullscreen_policy.gd")
const ASSETS=["architecture/metal_beam/v1","architecture/doorway/v1"]
var game: Node
var checks: Array=[]
var route: Array=[]
var points: Array[Vector3]=[]
var phase:=""
var frames: Array[float]=[]
var previous_us:=0
var height_value:=NAN
var height_token:=0
func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
    checks.append({"ok":ok,"label":label});print("PASS " if ok else "FAIL ",label)
func until(predicate: Callable,seconds: float=10.0) -> bool:
    var deadline:=Time.get_ticks_msec()+int(seconds*1000)
    while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
    return predicate.call()
func frame() -> void:
    var now:=Time.get_ticks_usec()
    if not phase.is_empty() and previous_us>0:frames.append((now-previous_us)/1000.0)
    previous_us=now
func pose(point: Vector3,scale: Vector3) -> PackedFloat32Array:
    return PackedFloat32Array([scale.x,0,0,point.x,0,scale.y,0,point.y,0,0,scale.z,point.z])
func batch(index: int) -> Node3D:return game.structures.model(ASSETS[index])
func collision_present(point: Vector3,id: int) -> bool:
    var hit: Dictionary=game.structures.blocks.raycast_scene(point+Vector3(0,0.9,0),point-Vector3(0,0.3,0),2,[])
    return not hit.is_empty() and hit.collider==batch(0) and batch(0).placement_for_body(hit.rid)==id
func visit(index: int,label: String) -> void:
    var point:=points[index]
    game.player.position=point+Vector3(14,7,30);game.fly=true;game.needs_floor_spawn=false
    game.camera.look_at(point+Vector3(14,0,6))
    phase=label;frames.clear();previous_us=Time.get_ticks_usec()
    var started:=Time.get_ticks_usec()
    var first_id:=index*128+1
    var ready: bool=await until(func():return batch(0).get_instance(first_id).size()==12 and batch(1).get_instance(first_id).size()==12 and batch(0).stats().slot_entries>=128 and batch(1).stats().slot_entries>=128 and collision_present(point,first_id),10)
    var arrival_ms:=(Time.get_ticks_usec()-started)/1000.0
    var until_ms:=Time.get_ticks_msec()+2000
    while Time.get_ticks_msec()<until_ms:await process_frame
    phase="" # Exclude screenshot capture and its following frame from timing.
    var sorted:=frames.duplicate();sorted.sort()
    var result:={"phase":label,"ready":ready,"arrival_ms":arrival_ms,"samples":frames.size(),"frames_ms":frames.duplicate(),"p95_ms":sorted[int((sorted.size()-1)*0.95)],"p99_ms":sorted[int((sorted.size()-1)*0.99)],"max_ms":sorted.back(),"models":[]}
    for a in 2:result.models.append({"storage":batch(a).region_stats(),"render":batch(a).render_stats(),"collision":batch(a).collision_stats()})
    route.append(result)
    check(ready,label+": saved models render and local collision becomes ready")
    check(batch(0).region_stats().resident_instances==128 and batch(1).region_stats().resident_instances==128,label+": only destination records remain resident")
    check(ready and arrival_ms<=1000,label+": arrival within 1000 ms")
    check(result.p95_ms<=18.5 and result.p99_ms<=25 and result.max_ms<=50,label+": frame gates p95 18.5 / p99 25 / max 50 ms")
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://reports/model_world_route/"+label+".png")
func save() -> bool:
    var count: int=game.model_paging.successful_saves
    game.terrain.save_world()
    return await until(func():return game.model_paging.successful_saves>count and game.model_paging.operation=="",15)
func run() -> void:
    DirAccess.make_dir_recursive_absolute("res://reports/model_world_route")
    game=load("res://demo/world.tscn").instantiate();root.add_child(game)
    process_frame.connect(frame)
    check(await until(func():return not game.loading_active and game.terrain.world_ready,60),"actual world starts")
    check(game.model_region_paging and game.model_paging!=null and Presentation.measurement(root).fair_graphical_sample,"opt-in main world at full-resolution 1080p fullscreen")
    if game.model_paging==null or not game.terrain.world_ready:await finish();return
    Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;game.fly=true;game.needs_floor_spawn=false
    game.terrain.height_received.connect(func(_p: Vector3,h: float,t: int):
        if t==height_token:height_value=h)
    for x in [256,896,1536]:
        var point:=Vector3(x+1,0,1025)
        height_token+=1;height_value=NAN;game.terrain.request_height(point,height_token)
        if not await until(func():return is_finite(height_value),5):check(false,"fixture height query");await finish();return
        point.y=height_value+4;points.append(point)
    for a in 2:
        var ids:=PackedInt64Array();var values:=PackedFloat32Array()
        for site in 3:
            for n in 128:
                ids.append(site*128+n+1)
                var p:=points[site]+Vector3((n%16)*2,1.3 if a==1 else 0,(n/16)*2)
                values.append_array(pose(p,Vector3.ONE if a==1 else Vector3(1.8,0.2,1.8)))
        check(batch(a).upsert_instances(ids,values),"author 384 placements for "+ASSETS[a])
    check(await save(),"fixture uses normal combined world save")
    # Reload forces metadata-first startup; authored resident data cannot fake arrival.
    var epoch: int=game.terrain.epoch
    game.terrain.reload_world()
    check(await until(func():return game.terrain.epoch>epoch and game.terrain.world_ready and game.model_paging.operation=="",30),"normal reload installs saved metadata")
    await visit(0,"near")
    await visit(2,"far")
    var edited:=pose(points[2]+Vector3(0,0.5,0),Vector3(1.8,0.2,1.8))
    check(game.model_tool.history.update(batch(0),257,edited,AABB()),"edit a streamed destination model")
    check(await save(),"normal save preserves streamed model edit")
    epoch=game.terrain.epoch;game.terrain.reload_world()
    check(await until(func():return game.terrain.epoch>epoch and game.terrain.world_ready and game.model_paging.operation=="",30),"edited world reloads")
    await visit(2,"far_reloaded")
    check(batch(0).get_instance(257)==edited,"exact edited transform survives reload")
    await visit(0,"return")
    check(game.model_paging.last_state.get("failed_transfers",0)==0,"no failed model transfers")
    await finish()
func finish() -> void:
    phase=""
    var failed:=0
    for row in checks:
        if not row.ok:failed+=1
    var result:={"checks":checks,"failures":failed,"route":route,"presentation":Presentation.measurement(root),"scope":"Actual main world, 768 static placements across two assets and three sites. Elevated geometric fixture over generated terrain; not a detailed city, a human playtest, thermal proof or sustained FPS qualification.","gates":{"arrival_ms":1000,"frame_p95_ms":18.5,"frame_p99_ms":25,"frame_max_ms":50},"slot":game.terrain.save_slot}
    var file:=FileAccess.open("res://reports/model_world_route/result.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
    game.shutdown_requested=true
    await game.terrain.shutdown_after_edits()
    print("MODEL_WORLD_ROUTE failures=",failed)
    quit(1 if failed else 0)
