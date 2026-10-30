# SPDX-License-Identifier: 0BSD
extends SceneTree
const Source=preload("res://reviews/civic_buildings/recipes.gd")
const IDS=Source.IDS
func _initialize()->void:
	for i in IDS.size():
		var candidate:=asset(i)
		if candidate==null or ResourceSaver.save(candidate,"res://addons/structures/prefabs/civic_review_"+IDS[i]+".tres")!=OK:quit(1);return
	print("CIVIC_REVIEW_BAKE failures=0");quit()
func asset(index:int)->Resource:
	if index<0 or index>=IDS.size():return null
	var source:Resource=load("res://reviews/civic_buildings/baked/"+IDS[index]+".tres")
	var result:Resource=source.duplicate()
	var lift:=0 if index==0 else 4
	var records:PackedInt32Array=source.get_records()
	for offset in range(1,records.size(),4):records[offset]+=lift
	if not result.configure(records):return null
	var attachments:Array=source.get_model_attachments()
	for row:Dictionary in attachments:row.transform.origin.y+=lift
	if not result.configure_model_attachments(attachments):return null
	for key in ["stair_routes","door_routes"]:
		var routes:Array=source.get_meta(key,[]).duplicate(true)
		for route:Dictionary in routes:
			for point_key in ["start","end"]:
				if route.has(point_key):route[point_key].y+=lift
		result.set_meta(key,routes)
	result.set_meta("civic_id",IDS[index])
	result.set_meta("site_surface_offset",1+lift)
	result.set_meta("site_sample_band",1+lift)
	result.set_meta("terrain_contact_version",preload("res://addons/structures/terrain_contact.gd").VERSION)
	var arrival:Dictionary=source.get_meta("stair_routes").filter(func(row):return row.kind in ["arrival","loading bay"])[0]
	result.set_meta("site_entrance",arrival.start+Vector3(0,lift-.02,.5))
	if index>0:
		var rect:Rect2i=Source.BASEMENTS[index]
		var sections:Array=[]
		# Overlapping narrow native cuts leave supporting terrain beneath the slab
		# and behind perimeter walls. They are part of the master earthworks plan.
		for x in range(rect.position.x+2,rect.end.x-1,2):sections.append(Vector2(x,rect.position.y+2))
		sections.append(Vector2(rect.end.x-2,rect.position.y+2))
		result.set_meta("cellar_clearance",true)
		result.set_meta("cellar_sections",sections)
		result.set_meta("cellar_end",float(rect.end.y-2))
		result.set_meta("cellar_floor",.75)
		result.set_meta("cellar_height",5.0)
	if index==4:result.set_meta("vehicle_entrances",PackedVector3Array([Vector3(13.5,5,34),Vector3(22.5,5,34)]))
	return result

