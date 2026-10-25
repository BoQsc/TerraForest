extends "res://reviews/modular_buildings/viewer.gd"

func _init() -> void:
	review_revision="A0 vs A2 / ROOF ONLY"

func review_designs() -> Array[Dictionary]:
	return [preload("res://reviews/modular_buildings/roof_recipe.gd").entry()]

func _ready() -> void:
	super()
	if not ready_ok:return
	for side in 2:
		var origin:=Vector3i(side*PAIR_OFFSET,0,0)
		var records:=PackedInt32Array()
		for column in [-2,1]:records.append_array(PackedInt32Array([origin.x+column,0,10,37]))
		for column in range(-2,2):
			for height in [1,2]:records.append_array(PackedInt32Array([origin.x+column,height,10,structures.blocks.encode_block(9,12,3)]))
		if not structures.blocks.set_cells(records):ready_ok=false;return
		var label:=Label3D.new();label.text="A0 / ORIGINAL\nUNCHANGED" if side==0 else "A2 / THIN ROOF\nAWAITING APPROVAL"
		label.position=Vector3(origin)+Vector3(0,2,11.015);label.font_size=48;label.pixel_size=.006
		label.modulate=Color("8ce8c1") if side==0 else Color("ffd38a");label.outline_size=10;add_child(label)
	structures.blocks.flush_bakes()
