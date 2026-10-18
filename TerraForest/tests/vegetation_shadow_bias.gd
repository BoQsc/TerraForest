# SPDX-License-Identifier: 0BSD
extends "res://tests/vegetation_lighting_world.gd"
func sample(label:String)->void:
 for batch in game.ground_cover.batches:batch.set_casts_shadows(false)
 for kind in [0,1,6,7]:game.ground_cover.batches[kind].set_casts_shadows(true)
 var bias:float=2.0
 if label=="understory_shadows":bias=0.5
 if label=="all_cover_shadows":bias=0.25
 game.sun.shadow_normal_bias=bias
 await super.sample("bias_"+str(bias)+"_"+label)
