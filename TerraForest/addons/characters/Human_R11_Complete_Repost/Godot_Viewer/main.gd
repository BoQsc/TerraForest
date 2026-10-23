extends Node3D
## Lightweight independent viewer for the exact R11 GLB.
## It does not reproduce the original 468 MB project's state machine.

var character: Node3D
var animation_player: AnimationPlayer
var camera: Camera3D
var info: Label
var clip_menu: OptionButton
var equipment_menu: OptionButton
var outfit_menu: OptionButton
var style_menu: OptionButton
var grip_checkbox: CheckBox
var hair_checkbox: CheckBox
var preview_checkbox: CheckBox
var speed_slider: HSlider
var third_person: bool = true
var yaw: float = 0.3
var pitch: float = 0.13
var distance: float = 3.5
var weapon: String = "Pickaxe"
var outfit: String = "Field"
var grip_right: bool = false
var style: int = 0
var manual_clip: bool = false
var active_clip: String = ""
var action_remaining: float = 0.0
var actor_meshes: Array[MeshInstance3D] = []
var optional_ak: Node3D

func _ready() -> void:
    _build_stage()
    _load_models()
    _build_camera()
    _build_ui()
    _set_equipment()
    _set_outfit()
    _set_hair()
    _set_optional_ak()
    _play_clip("Pickaxe_Idle")
    _update_camera()

func _build_stage() -> void:
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.12, 0.15, 0.20)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.85, 0.88, 1.0)
    environment.ambient_light_energy = 0.75
    var world := WorldEnvironment.new()
    world.environment = environment
    add_child(world)

    var sunlight := DirectionalLight3D.new()
    sunlight.rotation_degrees = Vector3(-47, -30, 0)
    sunlight.light_energy = 2.0
    sunlight.shadow_enabled = true
    add_child(sunlight)

    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-33, 120, 0)
    fill.light_energy = 0.65
    add_child(fill)

    var ground := MeshInstance3D.new()
    var ground_mesh := PlaneMesh.new()
    ground_mesh.size = Vector2(12, 12)
    ground.mesh = ground_mesh
    var ground_material := StandardMaterial3D.new()
    ground_material.albedo_color = Color(0.20, 0.23, 0.24)
    ground_material.roughness = 1.0
    ground.material_override = ground_material
    ground.position.y = -0.025
    add_child(ground)

func _load_models() -> void:
    var source := load("res://models/Human.r11.glb") as PackedScene
    if source == null:
        push_error("Human.r11.glb failed to import")
        return
    character = source.instantiate() as Node3D
    if character == null:
        push_error("Human R11 model root is not Node3D")
        return
    add_child(character)
    animation_player = _find_animation_player(character)
    _collect_meshes(character)
    if animation_player == null:
        push_warning("No AnimationPlayer was found in the imported GLB")

    var ak_source := load("res://addons_optional/AK47_Ammo_Under15k.glb") as PackedScene
    if ak_source != null:
        optional_ak = ak_source.instantiate() as Node3D
        if optional_ak != null:
            add_child(optional_ak)
            optional_ak.position = Vector3(2.0, 0.9, 0.0)
            optional_ak.visible = false

func _find_animation_player(root: Node) -> AnimationPlayer:
    if root is AnimationPlayer:
        return root as AnimationPlayer
    for child in root.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _collect_meshes(root: Node) -> void:
    if root is MeshInstance3D:
        actor_meshes.append(root as MeshInstance3D)
    for child in root.get_children():
        _collect_meshes(child)

func _build_camera() -> void:
    camera = Camera3D.new()
    camera.fov = 63.0
    camera.near = 0.025
    camera.current = true
    add_child(camera)

func _make_label(parent: VBoxContainer, caption: String) -> void:
    var label := Label.new()
    label.text = caption
    parent.add_child(label)

func _make_button(parent: BoxContainer, caption: String, method: Callable) -> void:
    var button := Button.new()
    button.text = caption
    button.pressed.connect(method)
    parent.add_child(button)

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var panel := PanelContainer.new()
    panel.position = Vector2(12, 12)
    panel.custom_minimum_size = Vector2(320, 0)
    layer.add_child(panel)
    var column := VBoxContainer.new()
    panel.add_child(column)

    _make_label(column, "HUMAN R11 / 71 CLIPS / 14,997 TRIANGLES")
    _make_label(column, "Exact saved R11 model - lightweight viewer")
    _make_label(column, "Weapon (equipment model already inside R11):")
    equipment_menu = OptionButton.new()
    for name in ["None", "Pickaxe", "Axe", "Carbine"]:
        equipment_menu.add_item(name)
    equipment_menu.select(1)
    equipment_menu.item_selected.connect(_on_weapon_selected)
    column.add_child(equipment_menu)

    _make_label(column, "Clothing:")
    outfit_menu = OptionButton.new()
    for name in ["Field", "Work", "Trail", "Base"]:
        outfit_menu.add_item(name)
    outfit_menu.item_selected.connect(_on_outfit_selected)
    column.add_child(outfit_menu)

    hair_checkbox = CheckBox.new()
    hair_checkbox.text = "Short hair equipped"
    hair_checkbox.button_pressed = true
    hair_checkbox.toggled.connect(_on_hair_toggled)
    column.add_child(hair_checkbox)

    grip_checkbox = CheckBox.new()
    grip_checkbox.text = "Experimental: right-hand-led pickaxe grip (G)"
    grip_checkbox.toggled.connect(_on_grip_toggled)
    column.add_child(grip_checkbox)

    _make_label(column, "Swing style:")
    style_menu = OptionButton.new()
    for name in ["Original", "Right-leaning", "Tilted"]:
        style_menu.add_item(name)
    style_menu.item_selected.connect(_on_style_selected)
    column.add_child(style_menu)

    _make_label(column, "Play any exact GLB clip (including all FP clips):")
    clip_menu = OptionButton.new()
    if animation_player != null:
        for anim_name in animation_player.get_animation_list():
            clip_menu.add_item(String(anim_name))
    clip_menu.item_selected.connect(_on_clip_selected)
    column.add_child(clip_menu)

    var row_a := HBoxContainer.new()
    column.add_child(row_a)
    _make_button(row_a, "Idle", _on_idle)
    _make_button(row_a, "Walk", _on_walk)
    _make_button(row_a, "Run", _on_run)
    _make_button(row_a, "Jump", _on_jump)
    _make_button(row_a, "Attack", _on_attack)

    var row_b := HBoxContainer.new()
    column.add_child(row_b)
    _make_button(row_b, "3P/1P (F)", _toggle_camera)
    _make_button(row_b, "Pause/Play (P)", _toggle_pause)
    _make_button(row_b, "Live keys", _restore_live)

    preview_checkbox = CheckBox.new()
    preview_checkbox.text = "Show separate AK-47 sample at right (not rigged)"
    preview_checkbox.toggled.connect(_on_ak_toggled)
    column.add_child(preview_checkbox)

    _make_label(column, "Playback speed:")
    speed_slider = HSlider.new()
    speed_slider.min_value = 0.1
    speed_slider.max_value = 2.0
    speed_slider.step = 0.1
    speed_slider.value = 1.0
    speed_slider.value_changed.connect(_on_speed_changed)
    column.add_child(speed_slider)

    info = Label.new()
    info.text = ""
    column.add_child(info)
    var help := Label.new()
    help.text = "WASD: preview locomotion  Shift: run  Space: jump\nLMB: swing/fire   Right-drag: orbit   Wheel: zoom\n1 carbine  2 pickaxe  3 axe  4 none\nG: grip  J: swing style  F: camera  P: pause"
    column.add_child(help)
    _refresh_info()

func _find_clip(requested: String) -> String:
    if animation_player == null:
        return ""
    for clip in animation_player.get_animation_list():
        var actual := String(clip)
        if actual == requested or actual.ends_with("/" + requested):
            return actual
    return ""

func _play_clip(requested: String, one_shot: bool = false) -> void:
    if animation_player == null:
        return
    var resolved := _find_clip(requested)
    if resolved.is_empty():
        push_warning("Clip not found: " + requested)
        return
    if resolved != active_clip or not animation_player.is_playing():
        animation_player.play(resolved, 0.12)
        active_clip = resolved
    if one_shot:
        action_remaining = animation_player.get_animation(resolved).length
    _refresh_info()

func _preferred_clip(action: String) -> String:
    if weapon == "None":
        return action
    var prefix := ""
    if weapon == "Carbine":
        prefix = "Rifle"
    elif weapon == "Pickaxe":
        prefix = "Pickaxe_RightGrip" if grip_right else "Pickaxe"
    else:
        prefix = "Axe"
    if not third_person:
        prefix = "FP_" + prefix
    var suffix := action
    if action == "Swing" or action == "Fire":
        if weapon == "Carbine":
            suffix = "Fire"
        else:
            suffix = "Swing"
            if style == 1:
                suffix += "_Right"
            elif style == 2:
                suffix += "_Tilt"
    return prefix + "_" + suffix

func _play_motion(motion: String, one_shot: bool = false) -> void:
    var clip := _preferred_clip(motion)
    if _find_clip(clip).is_empty():
        clip = motion
    _play_clip(clip, one_shot)

func _set_equipment() -> void:
    for mesh in actor_meshes:
        var lower := String(mesh.name).to_lower()
        if lower.begins_with("equipment."):
            var item_name := ""
            if lower.contains("pickaxe"):
                item_name = "Pickaxe"
            elif lower.contains("axe"):
                item_name = "Axe"
            elif lower.contains("carbine"):
                item_name = "Carbine"
            mesh.visible = weapon == item_name

func _set_outfit() -> void:
    for mesh in actor_meshes:
        var lower := String(mesh.name).to_lower()
        if not lower.begins_with("wardrobe."):
            continue
        if lower.contains("trousers") or lower.contains("boots"):
            mesh.visible = outfit != "Base"
        elif lower.contains("workshirt"):
            mesh.visible = outfit == "Work" or outfit == "Field"
        elif lower.contains("fieldvest"):
            mesh.visible = outfit == "Trail" or outfit == "Field"

func _set_hair() -> void:
    for mesh in actor_meshes:
        if String(mesh.name).to_lower().begins_with("hair."):
            mesh.visible = hair_checkbox.button_pressed

func _set_optional_ak() -> void:
    if optional_ak != null and preview_checkbox != null:
        optional_ak.visible = preview_checkbox.button_pressed

func _update_camera() -> void:
    if camera == null:
        return
    if third_person:
        var target := Vector3(0, 1.05, 0)
        var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        camera.position = target + direction * distance
        camera.look_at(target, Vector3.UP)
    else:
        camera.position = Vector3(0, 1.65, 0.03)
        camera.rotation = Vector3(0, PI, 0)

func _process(delta: float) -> void:
    if action_remaining > 0.0:
        action_remaining -= delta * (speed_slider.value if speed_slider != null else 1.0)
        if action_remaining <= 0.0:
            action_remaining = 0.0
            manual_clip = false
            _play_motion("Idle")
        return
    if manual_clip:
        return
    var moving := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D)
    var action := "Idle"
    if moving:
        action = "Run" if Input.is_key_pressed(KEY_SHIFT) else "Walk"
    var target_clip := _preferred_clip(action)
    if _find_clip(target_clip).is_empty():
        target_clip = action
    if active_clip != _find_clip(target_clip):
        _play_clip(target_clip)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
        yaw -= event.relative.x * 0.007
        pitch = clampf(pitch + event.relative.y * 0.007, -0.6, 1.15)
        _update_camera()
    elif event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            distance = maxf(1.5, distance - 0.3)
            _update_camera()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            distance = minf(8.0, distance + 0.3)
            _update_camera()
        elif event.button_index == MOUSE_BUTTON_LEFT:
            _on_attack()
    elif event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_1:
                equipment_menu.select(3)
                _on_weapon_selected(3)
            KEY_2:
                equipment_menu.select(1)
                _on_weapon_selected(1)
            KEY_3:
                equipment_menu.select(2)
                _on_weapon_selected(2)
            KEY_4:
                equipment_menu.select(0)
                _on_weapon_selected(0)
            KEY_G:
                grip_checkbox.button_pressed = not grip_checkbox.button_pressed
            KEY_J:
                style_menu.select((style + 1) % 3)
                _on_style_selected(style_menu.selected)
            KEY_F:
                _toggle_camera()
            KEY_P:
                _toggle_pause()
            KEY_SPACE:
                _on_jump()
            KEY_C:
                manual_clip = true
                var crouch_clip := "Pickaxe_RightGrip_Crouch" if weapon == "Pickaxe" and grip_right else "Crouch"
                _play_clip(crouch_clip)

func _on_clip_selected(index: int) -> void:
    manual_clip = true
    action_remaining = 0.0
    _play_clip(clip_menu.get_item_text(index))

func _on_weapon_selected(index: int) -> void:
    weapon = equipment_menu.get_item_text(index)
    manual_clip = false
    action_remaining = 0.0
    _set_equipment()
    _play_motion("Idle")

func _on_outfit_selected(index: int) -> void:
    outfit = outfit_menu.get_item_text(index)
    _set_outfit()

func _on_hair_toggled(_is_on: bool) -> void:
    _set_hair()

func _on_grip_toggled(is_on: bool) -> void:
    grip_right = is_on
    manual_clip = false
    action_remaining = 0.0
    _play_motion("Idle")

func _on_style_selected(index: int) -> void:
    style = index
    manual_clip = false
    _refresh_info()

func _on_ak_toggled(_is_on: bool) -> void:
    _set_optional_ak()

func _on_speed_changed(value: float) -> void:
    if animation_player != null:
        animation_player.speed_scale = value

func _on_idle() -> void:
    manual_clip = true
    action_remaining = 0.0
    _play_motion("Idle")

func _on_walk() -> void:
    manual_clip = true
    action_remaining = 0.0
    _play_motion("Walk")

func _on_run() -> void:
    manual_clip = true
    action_remaining = 0.0
    _play_motion("Run")

func _on_jump() -> void:
    manual_clip = false
    _play_motion("Jump", true)

func _on_attack() -> void:
    manual_clip = false
    _play_motion("Fire" if weapon == "Carbine" else "Swing", true)

func _toggle_camera() -> void:
    third_person = not third_person
    manual_clip = false
    action_remaining = 0.0
    _update_camera()
    _play_motion("Idle")

func _toggle_pause() -> void:
    if animation_player != null:
        if animation_player.is_playing():
            animation_player.pause()
            manual_clip = true
        else:
            animation_player.play()

func _restore_live() -> void:
    manual_clip = false
    action_remaining = 0.0
    _play_motion("Idle")

func _refresh_info() -> void:
    if info != null:
        info.text = "Now playing: %s\nView: %s   Equipment: %s   Grip: %s" % [
            active_clip, "Third person" if third_person else "First person",
            weapon, "Right-leading" if grip_right else "Original"
        ]
