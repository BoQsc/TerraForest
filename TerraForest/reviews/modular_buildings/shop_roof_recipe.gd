extends RefCounted

const Recipes = preload("res://reviews/modular_buildings/recipes.gd")
const PATH := "res://reviews/modular_buildings/baked/shop_roof_b2.tres"

static func build(blocks: Node3D) -> Resource:
	var source: Resource=Recipes.Workshop.village_shop()
	var cells:=Recipes.cells_of(source)
	for cell: Vector3i in cells.keys():
		if cell.y>=6:cells.erase(cell)
	for column in range(-6,7):
		var height:=12-absi(column)
		for row in range(-9,10):
			var origin:=Vector3i(column,height,row)
			if absi(row)==8:
				for level in range(6,height):cells[Vector3i(column,level,row)]=blocks.encode_block(1,0,1)
				cells[origin]=blocks.encode_block(12 if column==0 else 4,0 if column==0 else 3 if column<0 else 1,1)
			else:
				var orientation:=0 if column<=0 else 2
				cells[origin]=blocks.encode_block(17 if column==0 else 15,orientation,1)
				var seam:=origin+Vector3i.DOWN
				if not cells.has(seam):cells[seam]=blocks.encode_block(18 if column==0 else 16,orientation,1)
	var result:=Recipes.finish(source,cells,"Village shop B2 / thin gable roof / review R2")
	if result!=null:result.set_meta("review_revision",2)
	return result

static func entry() -> Dictionary:
	return {"title":"SHOP ROOF B2", "decision":"pending", "original":Recipes.Workshop.village_shop(),
		"candidate":load(PATH), "base":Vector3i.ZERO,
		"details":"B0 original left / B2 roof-only trial right / A2 thin roof system / shop layout unchanged / B1 untouched",
		"eye":Vector3(22,16,30), "aim":Vector3(.5,6,.5),
		"inside":Vector3(.5,3,6), "inside_aim":Vector3(-2,8,-2),
		"feature_eye":Vector3(4,11,19), "feature_aim":Vector3(-2.5,10,8.5),
		"remove":Vector3i(-3,9,9), "remove_view":2, "remove_label":"Remove ONE roof block", "floor":1.0,"approach":11.0}
