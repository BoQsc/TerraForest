# SPDX-License-Identifier: 0BSD
extends SceneTree
const DIR="res://reports/connected_world/"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Presentation=preload("res://addons/presentation/fullscreen_policy.gd")
var checks: Array=[]
static func ready_lakes(game: Node) -> bool:
    if game.lakes._lakes.size()!=4:return false
    for item: Dictionary in game.lakes._lakes.values():
        if item.volume==null or item.dirty or game.lakes.depth_at(item.seed)<=0:return false
    return true
static func snapshots(game: Node) -> Dictionary:
    var result:={"blocks":game.structures.blocks.capture_snapshot(),"models":game.structures.model("architecture/metal_beam/v1").capture_snapshot(),"lakes":game.lakes.capture_snapshot(),"roads":game.road_palette.capture_anchors()}
    for name in ["table","chair","shelf"]:result[name]=game.structures.model("furniture/"+name+"/v1").capture_snapshot()
    return result
static func write_bytes(path: String,bytes: PackedByteArray) -> void:
    var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
static func capture(game: Node,target: Vector3i) -> bool:
    DirAccess.make_dir_recursive_absolute(DIR)
    # A small static interior prop exercises the separate model provider too.
    var point:=Vector3(target)+Vector3(4,3,-12)
    var batch: Node3D=game.structures.model("architecture/metal_beam/v1")
    if "--furnished-settlement-fixture" not in OS.get_cmdline_user_args() and not batch.upsert_instances(PackedInt64Array([9001]),PackedFloat32Array([2,0,0,point.x,0,0.2,0,point.y,0,0,1,point.z])):return false
    var deadline:=Time.get_ticks_msec()+60000
    while not ready_lakes(game) and Time.get_ticks_msec()<deadline:await game.get_tree().process_frame
    if not ready_lakes(game):return false
    var saved: Array=[]
    var done:=func(ok: bool):saved.append(ok)
    game.terrain.save_completed.connect(done)
    game.terrain.save_world();deadline=Time.get_ticks_msec()+15000
    while saved.is_empty() and Time.get_ticks_msec()<deadline:await game.get_tree().process_frame
    game.terrain.save_completed.disconnect(done)
    if saved.is_empty() or not saved[0]:return false
    for name: String in snapshots(game):write_bytes(DIR+name+".bin",snapshots(game)[name])
    var manifest:={"slot":game.terrain.save_slot,"cells":game.structures.blocks.stats().cells,"target":[target.x,target.y,target.z],"generator":game.terrain.backend.world_generator,"seed":game.terrain.backend.world_seed,"presentation":Presentation.measurement(game.get_window()),"road_count":game.road_palette.prepared_streets.size(),"lake_count":game.lakes._lakes.size()}
    var core: RefCounted=game.terrain.backend.native
    game.shutdown_requested=true
    if not await game.terrain.shutdown_after_edits():return false
    # The worker is joined; direct native reads cannot race terrain mutations.
    write_bytes(DIR+"terrain.bin",core.execute(Codec.command(4)))
    var file:=FileAccess.open(DIR+"manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify(manifest,"  "));file.close()
    return true
func check(ok: bool,label: String) -> void:
    checks.append({"ok":ok,"label":label});print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DIR+"manifest.json"))
    var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
    var deadline:=Time.get_ticks_msec()+60000
    while (game.loading_active or not game.terrain.world_ready or game.structures.blocks.stats().cells!=int(manifest.cells) or not ready_lakes(game)) and Time.get_ticks_msec()<deadline:await process_frame
    check(not game.loading_active and game.terrain.world_ready,"fresh process loads playable world")
    check(not game.temporary_world and game.terrain.save_slot==manifest.slot,"fresh process opens the exact persistent slot")
    check(game.terrain.backend.world_generator==manifest.generator and game.terrain.backend.world_seed==manifest.seed and int(manifest.generator)==4,"geology/lake generator and seed survive reopen")
    check(Presentation.measurement(root).fair_graphical_sample and Engine.max_fps==60,"reopen uses 1080p fullscreen at 100 percent scale and 60 FPS cap")
    for name: String in snapshots(game):check(snapshots(game)[name]==FileAccess.get_file_as_bytes(DIR+name+".bin"),"exact "+name+" state survives fresh process")
    check(ready_lakes(game),"all four saved lake definitions rebake into occupied water")
    check(game.road_palette.prepared_streets.size()==4,"all connected roads restore in the editor catalog")
    check(game.structures.blocks.stats().cells==int(manifest.cells),"all four cottages restore as ordinary editable blocks")
    if "--furnished-settlement-fixture" in OS.get_cmdline_user_args():
        for name in ["table","chair","shelf"]:check(game.structures.model("furniture/"+name+"/v1").get_ids().size()==4,"four generated "+name+" objects restore")
    var target:=Vector3(manifest.target[0],manifest.target[1],manifest.target[2])
    game.fly=true;game.player.position=target+Vector3(40,35,40);game.needs_floor_spawn=false
    game.camera.look_at(target+Vector3(5,2,12))
    for frame in 60:await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(DIR+"reopened.png")
    if "--furnished-settlement-fixture" in OS.get_cmdline_user_args():
        game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false;game.fly=false
        game.player.position=Vector3(target.x+4.5,target.y+2.1,game.road_palette.prepared_streets[0].ends[0].z-11.0)
        game.yaw=0.0;game.pitch=-0.15;game.player.rotation.y=0
        game.camera.global_position=game.player.position+Vector3(0,1.6,0);game.camera.rotation=Vector3(game.pitch,0,0)
        game.terrain.focus=game.player.position;game.structures.set_model_focus(game.player.position)
        for frame in 60:await process_frame
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(DIR+"generated_interior.png")
    var core: RefCounted=game.terrain.backend.native
    game.shutdown_requested=true
    check(await game.terrain.shutdown_after_edits(),"reopened world closes through normal save lifecycle")
    check(core.execute(Codec.command(4))==FileAccess.get_file_as_bytes(DIR+"terrain.bin"),"exact generated and edited terrain survives fresh process")
    var asphalt:=true
    for street: Dictionary in game.road_palette.prepared_streets:
        for t in [0.0,0.5,1.0]:
            var point: Vector3=street.ends[0].lerp(street.ends[1],t)
            var query:=Codec.point_command(point-Vector3.UP);query.encode_u32(0,26)
            var reply: PackedByteArray=core.execute(query)
            asphalt=asphalt and Codec.reply_ok(reply) and reply.decode_u32(12)==4 and reply.decode_float(16)<0
    check(asphalt,"saved streets retain asphalt at ends and midpoints")
    var failed:=checks.filter(func(row):return not row.ok).size()
    var file:=FileAccess.open(DIR+"reopen.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failed,"scope":"Two actual graphical processes, generated terrain/geology/lakes, connected settlement, static prop and road catalog. Correctness and presentation; no performance or endurance claim."},"  "));file.close()
    quit(1 if failed else 0)
