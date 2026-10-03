# SPDX-License-Identifier: 0BSD
extends SceneTree

# Isolate production request ordering and coverage, without generation or GPU cost.
# A completed request installs one clean tile; counts are dependencies, not timings.
func _initialize() -> void:
	if not ClassDB.class_exists("NativeTerrainPlanner"):
		GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	run.call_deferred()

func run() -> void:
	var planner=ClassDB.instantiate("NativeTerrainPlanner")
	var rows: Array=[]
	var failures:=0
	for focus in [Vector3(1200,100,1334),Vector3(1024,100,1024),Vector3(1990,100,1990)]:
		var tiles: Dictionary={}
		var visible: Array=[]
		for z in range(0,2048,256):
			for x in range(0,2048,256):
				var key:=Vector3i(x,z,256)
				tiles[key]={"dirty":false,"used":0}
				visible.append(key)
		var split: Dictionary={}
		var trace: Array=[]
		var first_resident:=-1
		var first_active:=-1
		var target:=Vector3i(floori(focus.x/16)*16,floori(focus.z/16)*16,16)
		for step in range(1000):
			var plan: Dictionary=planner.requests(focus,true,tiles,split,visible)
			split=plan.split_state
			if plan.requests.is_empty(): break
			var next: Vector3i=plan.requests[0]
			tiles[next]={"dirty":false,"used":step}
			var coverage: Dictionary=planner.coverage(tiles,split,visible)
			visible=coverage["keys"]
			if coverage.root_coverage!=64: failures+=1
			trace.append([next.x,next.y,next.z])
			if first_resident<0 and tiles.has(target): first_resident=step+1
			if visible.has(target):
				first_active=step+1
				break
		# One fine target plus at most three siblings at each of four levels.
		# Cold startup must finish this closure before unrelated detail.
		if first_active<0 or first_active>13 or first_resident!=1: failures+=1
		var row: Dictionary={"focus":[focus.x,focus.y,focus.z],"target_resident_after_jobs":first_resident,"target_active_after_jobs":first_active,"jobs":trace}
		rows.append(row)
		print("LOADING_ORDER ",JSON.stringify(row))
	var report: Dictionary={"failures":failures,"rows":rows,"scope":"Production native planner with coarse world initially resident. Instant clean synthetic completions isolate dependency ordering. No generation cost, streaming throughput or graphical performance claim."}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/terrain_loading_order_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	planner=null
	quit(1 if failures else 0)
