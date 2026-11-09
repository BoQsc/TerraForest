# SPDX-License-Identifier: 0BSD
extends Node3D
## Original procedural muzzle VFX. +Z is the bore direction; units are metres.
## Three flash cards, three reusable smoke wisps and one short unshadowed light.
const FLASH = preload("res://addons/characters/runtime/muzzle_flash.gdshader")
const SMOKE = preload("res://addons/characters/runtime/muzzle_smoke.gdshader")
const FLASH_SECONDS := .038
const SMOKE_SECONDS := .55
var cards: Array[MeshInstance3D] = []
var smoke: Array[Dictionary] = []
var lamp: OmniLight3D
var random := RandomNumberGenerator.new()
var age := FLASH_SECONDS
var fresh := false
var bursts := 0
var next_wisp := 0
var pulse := 1.0

func _ready() -> void:
    random.randomize()
    for i in 3:
        var material := ShaderMaterial.new(); material.shader = FLASH
        material.set_shader_parameter("face_on", i == 2)
        var card := make_card(Vector2(.12, .14) if i < 2 else Vector2(.11, .11), material)
        card.name = "MuzzleCore" if i == 2 else "MuzzleGas%d" % i
        if i < 2:
            card.basis = Basis(Vector3.BACK, i * PI / 2) * Basis(Vector3.RIGHT, PI / 2)
            card.position.z = .07
        else: card.position.z = .012
        cards.append(card)
    for i in 3:
        var material := ShaderMaterial.new(); material.shader = SMOKE
        var wisp := make_card(Vector2(.16, .16), material)
        wisp.name = "MuzzleSmoke%d" % i
        wisp.top_level = true # Gas stays at the shot origin when the pistol recoils.
        smoke.append({"node": wisp, "age": SMOKE_SECONDS, "origin": Vector3.ZERO, "velocity": Vector3.ZERO})
    lamp = OmniLight3D.new(); lamp.name = "MuzzleLight"
    lamp.position.z = .035; lamp.light_color = Color("ffddae")
    lamp.omni_range = 1.5; lamp.omni_attenuation = 1.6
    lamp.shadow_enabled = false; lamp.light_cull_mask = 0xfffff
    add_child(lamp); lamp.hide()
    set_process(false)

func make_card(size: Vector2, material: ShaderMaterial) -> MeshInstance3D:
    var card := MeshInstance3D.new(); var quad := QuadMesh.new(); quad.size = size
    card.mesh = quad; card.material_override = material
    card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    card.layers = 1 << 19; add_child(card); card.hide()
    return card

func fire() -> void:
    if not is_visible_in_tree(): return
    bursts += 1; age = 0.0; fresh = true
    pulse = random.randf_range(.85, 1.1)
    var seed := random.randf_range(0.0, 100.0)
    var roll := random.randf_range(0.0, TAU)
    for i in cards.size():
        var card := cards[i]
        card.material_override.set_shader_parameter("seed", seed + i * 7.1)
        card.material_override.set_shader_parameter("strength", pulse)
        if i < 2:
            card.basis = Basis(Vector3.BACK, roll + i * PI / 2) * Basis(Vector3.RIGHT, PI / 2)
            card.scale = Vector3(random.randf_range(.82, 1.12), random.randf_range(.85, 1.15), 1.0)
            card.position.z = .07 * card.scale.y
        card.show()
    lamp.light_energy = .8 * pulse; lamp.show()
    var wisp: Dictionary = smoke[next_wisp]; next_wisp = (next_wisp + 1) % smoke.size()
    wisp.age = 0.0; wisp.origin = global_position + global_basis.z.normalized() * .025
    wisp.velocity = global_basis.z.normalized() * .22 + Vector3(random.randf_range(-.025, .025), .07, 0)
    wisp.node.global_position = wisp.origin
    wisp.node.material_override.set_shader_parameter("seed", seed)
    wisp.node.material_override.set_shader_parameter("age", 0.0); wisp.node.show()
    set_process(true)

func advance(delta: float) -> void:
    age += delta
    var intensity := pow(maxf(0.0, 1.0 - age / FLASH_SECONDS), 1.7) * pulse
    for card in cards:
        card.visible = age < FLASH_SECONDS
        card.material_override.set_shader_parameter("strength", intensity)
    lamp.visible = age < FLASH_SECONDS and is_visible_in_tree()
    lamp.light_energy = intensity * .8
    var active := age < FLASH_SECONDS
    for wisp in smoke:
        if wisp.age >= SMOKE_SECONDS: continue
        wisp.age += delta; wisp.node.visible = wisp.age < SMOKE_SECONDS
        wisp.node.global_position = wisp.origin + wisp.velocity * wisp.age + Vector3.UP * wisp.age * wisp.age * .08
        wisp.node.material_override.set_shader_parameter("age", wisp.age)
        active = active or wisp.age < SMOKE_SECONDS
    set_process(active)

func _process(delta: float) -> void:
    # An accepted shot must survive one rendered frame, even at low frame rates.
    if fresh: fresh = false; return
    advance(delta)
