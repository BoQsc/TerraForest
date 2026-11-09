# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
    var folder:="res://reports/firearm_impact_preview";DirAccess.make_dir_recursive_absolute(folder)
    var stage:=Node3D.new();root.add_child(stage)
    var world:=WorldEnvironment.new();world.environment=Environment.new()
    world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color("3f494b")
    world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=.7;stage.add_child(world)
    var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,-25,0);light.light_energy=1.5;stage.add_child(light)
    var camera:=Camera3D.new();stage.add_child(camera);camera.position=Vector3(.16,1.10,1.5);camera.look_at(Vector3(0,1,0));camera.fov=50;camera.current=true
    var panel:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=Vector3(1.2,1.2,.12);panel.mesh=mesh;panel.position=Vector3(0,1,-.06);stage.add_child(panel)
    var material:=StandardMaterial3D.new();material.roughness=.9;panel.material_override=material
    var effects=load("res://addons/impact_effects/impact_effects.gd").new();effects.settings_path="";stage.add_child(effects)
    var marks=load("res://addons/player_runtime/bullet_holes.gd").new();stage.add_child(marks)
    var title:=Label.new();title.position=Vector2(30,30);title.add_theme_font_size_override("font_size",26);root.add_child(title)
    # Warm each shader and the mark shader before capturing short-lived bursts.
    for kind in ["brick","wood","metal","flesh"]:effects.burst(Vector3(0,1,.01),Vector3.BACK,kind,false,true)
    marks.add(Vector3(0,1,0),Vector3.BACK)
    await create_timer(1.3).timeout
    for kind in ["brick","wood","metal","flesh"]:
        marks.clear();effects.clear_emitters()
        material.albedo_color={"brick":Color("736152"),"wood":Color("6d5842"),"metal":Color("646d71"),"flesh":Color("7d7770")}[kind]
        material.metallic=.6 if kind=="metal" else 0.0
        title.text="Firearm impact · "+kind+" · close-up"
        await process_frame;await RenderingServer.frame_post_draw
        if kind!="flesh":marks.add(Vector3(0,1,0),Vector3.BACK)
        effects.burst(Vector3(0,1,.01),Vector3.BACK,kind,false,true)
        for i in 3:await process_frame
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(folder.path_join(kind+"_burst.png"))
        await create_timer(.65).timeout;await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(folder.path_join(kind+"_settled.png"))
    stage.free();title.free();await process_frame;await process_frame;print("FIREARM_IMPACT_PREVIEW complete");quit()
