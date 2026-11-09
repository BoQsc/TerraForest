# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
    var folder:="res://reports/px9_flash"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--output="):folder=arg.trim_prefix("--output=")
    DirAccess.make_dir_recursive_absolute(folder)
    root.size=Vector2i(1280,720)
    var stage:=Node3D.new();root.add_child(stage)
    var environment:=WorldEnvironment.new();environment.environment=Environment.new()
    environment.environment.background_mode=Environment.BG_COLOR
    environment.environment.background_color=Color("667773")
    environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color=Color.WHITE
    environment.environment.ambient_light_energy=.6;stage.add_child(environment)
    var key:=DirectionalLight3D.new();key.rotation_degrees=Vector3(-45,-30,0);key.light_energy=1.5;stage.add_child(key)
    var wall:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(5,4,.1);wall.mesh=box
    var wall_material:=StandardMaterial3D.new();wall_material.albedo_color=Color("515553");wall.material_override=wall_material
    wall.position=Vector3(0,1,-2);stage.add_child(wall)
    var camera:=Camera3D.new();camera.fov=75;camera.near=.04;camera.position=Vector3(0,1.65,0);camera.current=true;stage.add_child(camera)
    var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools)
    var human:Node3D=tools.human;tools.set_process(false);human.set_process(false)
    var split=preload("res://addons/player_runtime/first_person_meshes.gd").new();split.prepare(tools);split.set_active(true);split.depth.set_active(true)
    tools.equip(9);human.handgun_empty=false;human._process(1)
    var label:=Label.new();label.position=Vector2(25,25);label.add_theme_font_size_override("font_size",24);root.add_child(label)
    var fx:Node3D=human.handgun_flash;fx.random.seed=910
    for aimed in [false,true]:
        for dark in [false,true]:
            key.light_energy=.08 if dark else 1.5
            environment.environment.ambient_light_energy=.045 if dark else .6
            var prefix:String=("aim" if aimed else "hip")+("_dim" if dark else "_day")
            human.px9.request("aim_idle" if aimed else "idle");human.px9.motion.seek_seconds(.1);split.sync()
            fx.advance(1);fx.set_process(false)
            await process_frame;await RenderingServer.frame_post_draw
            label.text="PX9 muzzle VFX · "+prefix+" · before"
            await process_frame;await RenderingServer.frame_post_draw
            root.get_texture().get_image().save_png(folder.path_join(prefix+"_before.png"))
            human.px9.request("aim_fire" if aimed else "fire");human.flash_handgun();fx.set_process(false)
            print(prefix," muzzle=",fx.global_position," forward=",fx.global_basis.z.normalized()," camera_direction=",-camera.global_basis.z)
            var sampled_time:=0.0
            for sample in [{"name":"flash","time":.0},{"name":"decay","time":.016},{"name":"smoke","time":.30}]:
                if sample.time>0:fx.advance(sample.time-sampled_time);fx.set_process(false);human.px9.motion.seek_seconds(sample.time)
                sampled_time=sample.time
                split.sync();label.text="PX9 muzzle VFX · "+prefix+" · "+sample.name
                await process_frame;await RenderingServer.frame_post_draw
                root.get_texture().get_image().save_png(folder.path_join(prefix+"_"+sample.name+".png"))
    split.dispose();stage.free();label.free();await process_frame
    print("PX9_FLASH_PREVIEW complete");quit()
