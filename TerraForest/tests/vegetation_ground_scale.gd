# SPDX-License-Identifier: 0BSD
extends "res://tests/vegetation_lighting_world.gd"
func sample(label:String)->void:
 for batch in game.ground_cover.batches:batch.set_casts_shadows(false)
 for kind in [0,1,6,7]:game.ground_cover.batches[kind].set_casts_shadows(true)
 var scale:float=1.0
 if label=="understory_shadows":scale=2.5
 if label=="all_cover_shadows":scale=4.0
 game.terrain.material.set_shader_parameter("grass_surface_scale",scale)
 await super.sample("ground_scale_"+str(scale)+"_"+label)
