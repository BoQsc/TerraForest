extends RefCounted
## Authoring adapter to the terrain transaction boundary, not a second mesher.
const Preset = preload("res://addons/structures/primitive_preset.gd")
const PRESETS: Array = [
	preload("res://addons/structures/presets/box.tres"),
	preload("res://addons/structures/presets/sphere.tres"),
	preload("res://addons/structures/presets/cylinder.tres"),
	preload("res://addons/structures/presets/slope.tres"),
	preload("res://addons/structures/presets/stairs.tres")]
var terrain: Node3D
var _inspector: RefCounted

func _ready_packet(command: PackedByteArray) -> bool:
	if terrain == null or not terrain.world_ready or terrain.pending_edit or command.is_empty():
		return false
	if _inspector == null:
		_inspector = ClassDB.instantiate("NativeTerrainStamp")
	var inspected: Dictionary = _inspector.inspect(command)
	if not inspected.get("valid",false):
		return false
	var bounds: AABB = inspected["edit_bounds"]
	# Readiness is required over the whole reconstruction footprint, including
	# tile boundaries. A center ray may otherwise hit a coarse fallback collider.
	for z in range(floori(bounds.position.z/16.0),floori(bounds.end.z/16.0)+1):
		for x in range(floori(bounds.position.x/16.0),floori(bounds.end.x/16.0)+1):
			if not terrain.player_region_ready(Vector3(x*16+8,0,z*16+8)):
				return false
	return true

func can_place(preset: Preset, center: Vector3, quarter_turns: int = 0) -> bool:
	return preset != null and _ready_packet(preset.packet(center,quarter_turns,true,1))

func place(preset: Preset, center: Vector3, quarter_turns: int = 0, material: int = 1, add: bool = true) -> bool:
	if terrain == null or preset == null:
		return false
	var command: PackedByteArray = preset.packet(center,quarter_turns,add,material)
	if not _ready_packet(command):
		return false
	# Terrain derives support bounds from the validated native packet.
	return terrain.edit(command,center,center)
