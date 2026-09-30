extends SceneTree
## Quantify observer overhead independently of gameplay frames.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var packed := FileAccess.get_file_as_bytes("res://docs/evidence/foundation_mining/scale_16/foundation_mining.json.gz")
	var fixture: Dictionary=JSON.parse_string(packed.decompress_dynamic(64*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	var samples: Array[Dictionary]=[]
	for count in range(1,fixture.phases.size()+1):
		var full: Dictionary=fixture.duplicate()
		full["phases"]=fixture.phases.slice(0,count)
		var compact: Dictionary=full.duplicate()
		var progress: Array[Dictionary]=[]
		for phase in full.phases:
			var row: Dictionary=phase.duplicate()
			for key in ["edits","patch_work","stages"]: row.erase(key)
			progress.append(row)
		compact["phases"]=progress
		for repeat in range(3):
			var begin := Time.get_ticks_usec()
			var text := JSON.stringify(full,"  ")
			var full_ms := (Time.get_ticks_usec()-begin)/1000.0
			var full_size := text.length()
			begin=Time.get_ticks_usec()
			var compact_text := JSON.stringify(compact,"  ")
			var compact_ms := (Time.get_ticks_usec()-begin)/1000.0
			samples.append({"phases":count,"repeat":repeat,"full_ms":full_ms,"compact_ms":compact_ms,"full_chars":full_size,"compact_chars":compact_text.length()})
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/foundation_observer.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"samples":samples,"scope":"Godot JSON serialization only, using retained pressure trace. Excludes gameplay and disk I/O."},"  "))
	file.close()
	print("OBSERVER ",JSON.stringify(samples))
	quit()
