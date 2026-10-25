extends "res://reviews/modular_buildings/roof_viewer.gd"

func _init() -> void:
	review_revision="B0 vs B2 / ROOF ONLY"
	sign_distance=12
	sign_texts=["B0 / ORIGINAL\nUNCHANGED","B2 / THIN ROOF\nAPPROVED DEFAULT"]

func review_designs() -> Array[Dictionary]:
	return [preload("res://reviews/modular_buildings/shop_roof_recipe.gd").entry()]
