extends RefCounted

const NAMES: Array[String] = ["Cube", "Slab", "Stairs", "Slope", "Post", "Sphere", "Round column", "Top plate", "Thin panel", "Frame corner", "Quarter arch", "Roof ridge", "Outer roof corner", "Inner roof corner", "Thin roof slope", "Roof seam infill", "Thin roof ridge", "Ridge seam infill", "Shallow roof low", "Shallow roof high", "Shallow roof seam", "Shallow ridge", "Shallow ridge seam", "Shallow hip low", "Shallow hip high", "Shallow valley low", "Shallow valley high", "Crown cornice", "Crown corner", "Beveled coping", "Coping corner", "Shallow gable low", "Shallow gable high", "Shallow gable ridge", "Pitched gable slope", "Pitched gable ridge"]
const MOUNTS: Array[String] = ["Upright", "Tip forward", "Upside down", "Tip backward", "Roll left", "Roll right"]

static func rotation_count(shape_id: int) -> int:
	return 24 if shape_id > 8 else 4

static func rotation_name(orientation: int) -> String:
	return "%s · %d°" % [MOUNTS[orientation / 4], (orientation % 4) * 90]

static func turn(shape_id: int, orientation: int, tilt: bool = false) -> int:
	if shape_id <= 8:
		return (orientation + 1) % 4
	if tilt:
		return ((orientation / 4 + 1) % 6) * 4 + orientation % 4
	return (orientation / 4) * 4 + (orientation + 1) % 4

const FAMILIES = ["All shapes", "Blocks & round", "Frame & arch", "Roof", "Cornice & coping"]
const APPEARANCES = ["Original material", "Aged brick", "Weathered plaster", "Coursed limestone", "Weathered timber", "Dark slate", "Patinated zinc", "Aged clay tile", "Soot-aged stone"]
static func family(shape_id: int) -> int:
	return 1 if shape_id <= 9 else (2 if shape_id <= 11 else (3 if shape_id <= 27 or shape_id >=32 else 4))
static func assembly_hint(shape_id: int) -> String:
	if shape_id>=32:return "Closed roof end: appearance coats the roof; end faces use the structural material. Combine cells to close the gable."
	if shape_id in [19, 20, 21]: return "1:2 roof: alternate low/high cells; add seam below each low phase."
	if shape_id in [22, 23]: return "1:2 ridge: use ridge above ridge seam; connect matching slopes on both sides."
	if shape_id in [24, 25, 26, 27]: return "1:2 corner: match low/high phase to adjacent slopes. Rotate hip or valley to the join."
	if shape_id in [28, 29]: return "Crown band: join straight cells to a rotated corner at the wall edge."
	if shape_id in [30, 31]: return "Parapet cap: straight runs meet a four-edge corner; one removable cell each."
	if shape_id in [15, 16, 17, 18]: return "1:1 roof: slope/ridge above matching seam infill."
	if shape_id == 11: return "Combine quarter arches and vertical panels around the opening."
	return "One grid cell per piece. R turns; Shift+R changes mounting direction."
