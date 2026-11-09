# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:run.call_deferred()
func run()->void:
    ProjectSettings.set_setting("terraforest/impact_effects_settings_path","")
    game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60
    game.terrain.backend.disk_cache.enabled=false;root.add_child(game)
    var deadline:=Time.get_ticks_msec()+90000
    while (game.loading_active or game.needs_floor_spawn) and Time.get_ticks_msec()<deadline:await process_frame
    check(not game.loading_active and not game.needs_floor_spawn,"temporary world ready")
    if game.loading_active or game.needs_floor_spawn:quit(1);return
    game.set_physics_process(false);game.combat.set_physics_process(false);game.player_view.set_process(false);game._clear_motion()
    game.player_view.entry.finish();game.app_focused=true
    if game.session_menu.developer:game.session_menu.toggle_developer()
    game.session_menu.set_open(false);game.zombies.clear();game.zombies.population_enabled=false;game.zombies.enabled=true
    var fx:Node=game.impact_effects;fx.set_enabled(true,false);fx.set_style(0,false)
    var combat:Node=game.combat
    var folder:="res://reports/firearm_impacts";DirAccess.make_dir_recursive_absolute(folder)
    var base:=Vector3i(game.player.global_position.floor())+Vector3i(0,6,0)
    var materials:=["brick","wood","concrete","metal"]
    var shots_before:int=combat.shots
    for i in 4:
        var cell:Vector3i=base+Vector3i(i*2,0,0)
        var word:int=game.structures.blocks.encode_block(1,0,i)
        check(game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,word])),"native test block inserted: "+materials[i])
        var centre:=Vector3(cell)+Vector3.ONE*.5
        var hit:Dictionary=game.structures.blocks.raycast_cells(centre+Vector3.BACK*2,centre-Vector3.BACK*2)
        check(not hit.is_empty(),"native cell ray resolves surface: "+materials[i])
        if hit.is_empty():continue
        hit.collider=game.structures.blocks
        var before:int=fx.emitted_events
        combat.impact(hit,Vector3.FORWARD,28,10)
        check(fx.emitted_events==before+1 and fx.last_event.material==materials[i] and fx.last_event.firearm,"confirmed block hit emits one correctly classified compact burst: "+materials[i])
        check(fx.last_event.count<10 and combat.impact_audio.last_material==materials[i],"small fragment budget and matching spatial audio: "+materials[i])
        check(game.world_attack.durability.damage(game.world_attack.block_key(cell),[90,60,120,180][i])==10,"feedback preserves single block damage: "+materials[i])
        if DisplayServer.get_name()!="headless":
            game.camera.global_position=centre+Vector3(.25,.20,1.7);game.camera.look_at(centre)
            await create_timer(.06).timeout;await RenderingServer.frame_post_draw
            root.get_texture().get_image().save_png(folder.path_join(materials[i]+".png"))
        fx.clear_emitters()
    check(combat.holes.holes.size()==4 and combat.holes.holes[0].node.material_override is ShaderMaterial,"hard surfaces receive irregular shader marks")
    var count:int=combat.holes.holes.size()
    combat.resolve_impact_feedback({"kind":"terrain","position":Vector3(base)+Vector3.UP*2,"normal":Vector3.UP})
    check(combat.holes.holes.size()==count and combat.impact_audio.last_material=="soil","soft ground emits a puff without a floating dark hole")
    fx.clear_emitters();fx.set_enabled(false,false)
    combat.resolve_impact_feedback({"kind":"block","material_id":1,"position":Vector3(base),"normal":Vector3.BACK})
    check(fx.pool.is_empty() and combat.impact_audio.last_material=="wood","particle toggle suppresses particles while preserving impact sound")
    fx.set_enabled(true,false)
    count=combat.holes.holes.size()
    var zombie:Node3D
    for offset in [Vector3(0,0,3),Vector3(3,0,0),Vector3(-3,0,0),Vector3(0,0,-3),Vector3(4,0,4),Vector3(-4,0,-4)]:
        zombie=game.zombies.spawn_at(game.player.global_position+offset)
        if zombie!=null:break
    check(zombie!=null,"zombie target spawns on actual terrain")
    if zombie!=null:
        zombie.set_behavior(false);zombie.set_physics_process(false);zombie.animation_player.pause();zombie.skeleton.force_update_all_bone_transforms()
        var mesh:ArrayMesh=zombie._bake_cpu(zombie.part_meshes.torso,Transform3D.IDENTITY)
        var point:=mesh.get_aabb().get_center()
        var health:float=zombie.health
        var emitted:int=fx.emitted_events
        var previous_audio:int=combat.impact_audio.played
        check(combat.launch(point+Vector3.BACK*.6,Vector3.FORWARD,9),"native projectile launches at the visible torso")
        combat.step_projectiles(.01)
        check(zombie.health<health and fx.emitted_events==emitted+1 and fx.last_event.material=="flesh","projectile damages actual zombie and emits one entrance burst")
        print("FLESH_AUDIO before=",previous_audio," after=",combat.impact_audio.played," material=",combat.impact_audio.last_material," voices=",combat.impact_audio.pool.size()," holes=",combat.holes.holes.size()," expected=",count)
        check(combat.impact_audio.played==previous_audio+1 and combat.impact_audio.last_material=="flesh" and combat.holes.holes.size()==count,"flesh impact sounds once and never leaves a floating bullet mark")
        if DisplayServer.get_name()!="headless":
            game.camera.global_position=point+Vector3.BACK*2;game.camera.look_at(point)
            await create_timer(.05).timeout;await RenderingServer.frame_post_draw
            root.get_texture().get_image().save_png(folder.path_join("flesh.png"))
    check(combat.shots==shots_before,"impact cosmetics do not invent trigger shots")
    for i in 16:combat.resolve_impact_feedback({"kind":"block","material_id":3,"position":Vector3(base),"normal":Vector3.BACK})
    check(fx.pool.size()<=8 and combat.impact_audio.pool.size()<=8,"rapid hits retain bounded particle and audio pools")
    combat.clear_transients()
    check(combat.holes.holes.is_empty() and combat.projectiles.is_empty(),"world reset clears marks and projectiles")
    var stopped:=true
    for voice in combat.impact_audio.pool:stopped=stopped and not voice.playing
    check(stopped,"world reset stops transient impact voices")
    game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"temporary world shuts down safely")
    game.free();await process_frame;await process_frame
    print("FIREARM_IMPACTS checks=",checks," failures=",failures);quit(1 if failures else 0)
