# SPDX-License-Identifier: 0BSD
extends SceneTree

const OUT := "res://addons/house_lights/assets"
var steel: StandardMaterial3D
var brass: StandardMaterial3D
var wood: StandardMaterial3D
var glow: StandardMaterial3D
var charcoal: StandardMaterial3D

func material(color: String, metal: float, roughness: float, emissive: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(color); result.metallic = metal; result.roughness = roughness
	if emissive:
		result.emission_enabled = true; result.emission = Color("ffaf55"); result.emission_energy_multiplier = 2.5
	return result

func part(owner: Node3D, mesh: PrimitiveMesh, point: Vector3, surface: Material, rotation: Vector3 = Vector3.ZERO) -> void:
	var node := MeshInstance3D.new(); mesh.material = surface; node.mesh = mesh
	node.position = point; node.rotation_degrees = rotation; owner.add_child(node); node.owner = owner

func box(owner: Node3D, point: Vector3, size: Vector3, surface: Material) -> void:
	var mesh := BoxMesh.new(); mesh.size = size; part(owner, mesh, point, surface)

func cylinder(owner: Node3D, point: Vector3, radius: float, height: float, surface: Material, top: float = -1, rotation: Vector3 = Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new(); mesh.bottom_radius = radius; mesh.top_radius = radius if top < 0 else top
	mesh.height = height; mesh.radial_segments = 16; mesh.rings = 1; part(owner, mesh, point, surface, rotation)

func flame(owner: Node3D, point: Vector3, scale: float) -> void:
	for angle in [0, 90]:
		var mesh := QuadMesh.new(); mesh.size = Vector2(.30, .44) * scale
		part(owner, mesh, point, glow, Vector3(0, angle, 0))

func lamp() -> Node3D:
	var root := Node3D.new(); root.name = "Caged room lamp"
	cylinder(root, Vector3(0, .045, 0), .28, .09, steel, .24)
	cylinder(root, Vector3(0, 1.0, 0), .028, 1.85, steel)
	cylinder(root, Vector3(0, 1.80, 0), .25, .07, brass, .22)
	cylinder(root, Vector3(0, 2.03, 0), .28, .13, steel, .12)
	flame(root, Vector3(0, 1.94, 0), .65)
	for index in 8:
		var angle := index * TAU / 8
		cylinder(root, Vector3(cos(angle) * .20, 1.92, sin(angle) * .20), .012, .25, steel)
	for height in [1.82, 2.00]:
		var ring := TorusMesh.new(); ring.inner_radius = .19; ring.outer_radius = .213
		ring.rings = 16; ring.ring_segments = 6; part(root, ring, Vector3(0, height, 0), brass)
	return root

func torch() -> Node3D:
	var root := Node3D.new(); root.name = "Standing pitch torch"
	cylinder(root, Vector3(0, .045, 0), .25, .09, steel)
	cylinder(root, Vector3(0, .62, 0), .048, 1.15, wood, .065)
	cylinder(root, Vector3(0, 1.20, 0), .105, .23, charcoal, .075)
	for height in [1.10, 1.23, 1.30]: cylinder(root, Vector3(0, height, 0), .111, .025, steel)
	flame(root, Vector3(0, 1.48, 0), 1.1)
	for index in 3:
		var angle := index * TAU / 3
		var foot := Vector3(cos(angle) * .17, .17, sin(angle) * .17)
		var mesh := CylinderMesh.new(); mesh.top_radius = .018; mesh.bottom_radius = .018; mesh.height = .35; mesh.radial_segments = 8
		part(root, mesh, foot, steel, Vector3(sin(angle) * 30, 0, cos(angle) * 30))
	return root

func fireplace() -> Node3D:
	var root := Node3D.new(); root.name = "Freestanding cast iron fireplace"
	box(root, Vector3(0, .12, 0), Vector3(1.18, .12, .7), steel)
	for side in [-1, 1]:
		box(root, Vector3(side * .58, .70, 0), Vector3(.10, 1.1, .7), steel)
		for front in [-1, 1]: cylinder(root, Vector3(side * .46, .07, front * .25), .065, .14, steel)
	box(root, Vector3(0, 1.27, 0), Vector3(1.28, .12, .78), steel)
	box(root, Vector3(0, .68, -.31), Vector3(1.1, 1.03, .08), charcoal)
	box(root, Vector3(0, .30, 0), Vector3(1.08, .08, .60), charcoal)
	box(root, Vector3(0, .40, .29), Vector3(1.06, .12, .06), brass)
	for side in [-1, 1]:
		cylinder(root, Vector3(side * .27, .40, -.01), .09, .57, wood, -1, Vector3(90, side * 18, 0))
		flame(root, Vector3(side * .23, .70, -.01), 1.45)
	cylinder(root, Vector3(0, 1.39, -.12), .17, .18, brass)
	cylinder(root, Vector3(0, 1.78, -.12), .125, .65, steel)
	cylinder(root, Vector3(0, 2.12, -.12), .21, .06, steel)
	for column in range(-4, 5): box(root, Vector3(column * .115, .65, .30), Vector3(.018, .54, .025), steel)
	return root

func _initialize() -> void:
	steel = material("333c42", .78, .52); brass = material("8b7050", .72, .5)
	wood = material("5c3822", 0, .93); charcoal = material("20201e", .15, .95); glow = material("ffbd62", 0, .6, true)
	glow.resource_name = "TerraForestFlame"
	DirAccess.make_dir_recursive_absolute(OUT)
	for kind: String in ["room_lamp", "standing_torch", "iron_fireplace"]:
		var node := lamp() if kind == "room_lamp" else torch() if kind == "standing_torch" else fireplace()
		var merged := ArrayMesh.new()
		for surface: Material in [steel, brass, wood, glow, charcoal]:
			var builder := SurfaceTool.new(); builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			var count := 0
			for child: MeshInstance3D in node.get_children():
				if child.mesh.material == surface:
					builder.append_from(child.mesh, 0, child.transform); count += 1
			if count > 0: builder.set_material(surface); builder.commit(merged)
		for child: Node in node.get_children(): child.free()
		var instance := MeshInstance3D.new(); instance.mesh = merged; node.add_child(instance); instance.owner = node
		var document := GLTFDocument.new(); var state := GLTFState.new()
		if document.append_from_scene(node, state) != OK or document.write_to_filesystem(state, OUT.path_join(kind + ".glb")) != OK:
			node.free(); quit(1); return
		node.free()
		var importer := preload("res://addons/structures/object_mesh.gd").new()
		var baked: Mesh = importer.load_visual({"source": kind + ".glb"}, OUT)
		if baked == null: push_error(importer.error); quit(1); return
		baked.set_meta("source_glb_sha256", FileAccess.get_sha256(OUT.path_join(kind + ".glb")))
		if ResourceSaver.save(baked, OUT.path_join(kind + "_model.res")) != OK: quit(1); return
		print("AUTHORED_LIGHT ", kind)
	quit()
