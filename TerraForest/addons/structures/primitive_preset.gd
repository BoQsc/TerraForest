@tool
extends Resource
## Reusable authoring configuration. Density sampling and edits execute in C++.
enum Shape { SPHERE, BOX, CYLINDER, SLOPE, STAIRS }
@export var title: String = "Primitive"
@export var shape: Shape = Shape.BOX
@export var half_extents := Vector3(4,3,4)
@export_range(1,16,1) var steps: int = 1

func packet(center: Vector3, quarter_turns: int, add: bool, material: int) -> PackedByteArray:
	if not ClassDB.class_exists("NativeTerrainStamp"):
		GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	if not ClassDB.class_exists("NativeTerrainStamp"):
		return PackedByteArray()
	var stamp: RefCounted = ClassDB.instantiate("NativeTerrainStamp")
	if not stamp.configure(shape,center,half_extents,quarter_turns,steps):
		return PackedByteArray()
	return stamp.packet(add,material)
