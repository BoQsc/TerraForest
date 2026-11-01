# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [[Vector3(.13,.012,.025),Vector3(-.065,0,0),0.0],[Vector3(.15,.006,.008),Vector3(.07,0,0),0.0],[Vector3(.032,.006,.008),Vector3(.153,0,-.01),-.65],[Vector3(.18,.005,.008),Vector3(.025,0,.055),0.12],[Vector3(.008,.005,.027),Vector3(-.067,0,.067),0.12]]:
		var box:=BoxMesh.new();box.size=part[0]
		surface.append_from(box,0,Transform3D(Basis(Vector3.UP,part[2]),part[1]))
	var material:=StandardMaterial3D.new();material.albedo_color=Color("9cabb0");material.metallic=.65;material.roughness=.55
	surface.set_material(material)
	var mesh:=surface.commit()
	var error:=ResourceSaver.save(mesh,"res://addons/player_runtime/art/drops/213.res")
	var icon:=Image.new()
	if icon.load_svg_from_string(FileAccess.get_file_as_string("res://addons/player_runtime/art/lockpick.svg"))==OK:
		DirAccess.make_dir_recursive_absolute("res://reports/container_locks")
		icon.save_png("res://reports/container_locks/lockpick-icon.png")
	print("LOCKPICK_BAKE error=",error," bounds=",mesh.get_aabb())
	quit(0 if error==OK else 1)
