extends SceneTree

const Catalog=preload("res://addons/structures/city_catalog.gd")

func _initialize()->void:
	var entrances:=[Vector3(12.5,1,27.5),Vector3(10,1,19.5),Vector3(12,1,25.5),Vector3(12,1,23.5),Vector3(31.5,1,29.5),Vector3(11.5,1,19.5)]
	var vehicle_entries:=[PackedVector3Array([Vector3(4.5,1,27),Vector3(13.5,1,27)]),PackedVector3Array([Vector3(22.5,1,19)]),PackedVector3Array(),PackedVector3Array(),PackedVector3Array([Vector3(4.5,1,25),Vector3(13.5,1,25),Vector3(22.5,1,25)]),PackedVector3Array()]
	for index in Catalog.IDS.size():
		var reference:Resource=load("res://reviews/city_buildings/baked/"+Catalog.IDS[index]+".tres")
		var approved:Resource=reference.duplicate()
		approved.resource_name=Catalog.TITLES[index]
		approved.set_meta("review_only",false)
		approved.set_meta("approved_as_addition",true)
		approved.set_meta("approved_revision",Catalog.IDS[index]+" R1")
		approved.set_meta("approved_date","2026-10-28")
		approved.set_meta("city_id",Catalog.IDS[index])
		approved.set_meta("site_surface_offset",1)
		approved.set_meta("site_sample_band",1)
		approved.set_meta("site_entrance",entrances[index])
		approved.set_meta("vehicle_entrances",vehicle_entries[index])
		if ResourceSaver.save(approved,"res://addons/structures/prefabs/city_"+Catalog.IDS[index]+".tres")!=OK:quit(1);return
	print("APPROVED_CITY_BAKE failures=0");quit()
