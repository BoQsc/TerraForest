extends RefCounted

const Recipes = preload("res://reviews/modular_buildings/recipes.gd")
const PATH := "res://reviews/modular_buildings/baked/cottage_roof_a2.tres"

static func build(blocks: Node3D) -> Resource:
	var source: Resource=Recipes.Furniture.enclosed_cottage()
	var cells:=Recipes.cells_of(source)
	for cell: Vector3i in cells.keys():
		if cell.y>=6:cells.erase(cell)
	for column in range(-4,5):
		var height:=10-absi(column)
		for row in range(-6,7):
			var origin:=Vector3i(column,height,row)
			if absi(row)==5:
				for level in range(6,height):cells[Vector3i(column,level,row)]=blocks.encode_block(1,0,1)
				cells[origin]=blocks.encode_block(12 if column==0 else 4,0 if column==0 else 3 if column<0 else 1,1)
			else:
				var orientation:=0 if column<=0 else 2
				cells[origin]=blocks.encode_block(17 if column==0 else 15,orientation,1)
				var seam:=origin+Vector3i.DOWN
				if not cells.has(seam):cells[seam]=blocks.encode_block(18 if column==0 else 16,orientation,1)
	var result:=Recipes.finish(source,cells,"Cottage A2 / thin roof / review R2")
	if result!=null:result.set_meta("review_revision",2)
	return result

static func entry() -> Dictionary:
	return {"title":"COTTAGE ROOF A2", "decision":"pending", "original":Recipes.Furniture.enclosed_cottage(),
		"candidate":load(PATH), "base":Vector3i.ZERO,
		"details":"A0 original on left / A2 roof-only proposal on right / continuous thin slopes / unchanged doors, rooms and stairs",
		"eye":Vector3(15,10,23), "aim":Vector3(.5,5,.5),
		"inside":Vector3(.5,3.65,3.8), "inside_aim":Vector3(-2,7,-1),
		"feature_eye":Vector3(2,8.5,13), "feature_aim":Vector3(-1.7,8.4,5.7),
		"remove":Vector3i(-2,8,6), "remove_view":2, "remove_label":"Remove ONE roof block", "floor":2.0,"approach":10.0}
