# SPDX-License-Identifier: 0BSD
extends SceneTree
const Map=preload("res://addons/audio_runtime/kaino_audition_map.gd")
const Decoder=preload("res://addons/audio_runtime/wav_decoder.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	var catalog=preload("res://addons/audio_runtime/catalog.gd").new()
	var selection:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Map.DEFAULT_SELECTION)).selection
	for key:String in selection:catalog.sounds[key]={"loop":false,"files":[]}
	check(not selection.is_empty() and Map.apply(catalog)==selection.size(),"all selected bundled sounds resolve through the PCK-compatible resource path")
	for key:String in selection:
		var path:String=selection[key]
		var sound:AudioStreamWAV=Decoder.decode(path)
		check(sound!=null and sound.get_length()>0 and sound.data.size()>0,"unchanged raw sound decodes: "+key)
		if sound!=null:print("AUDIO_PACK_STREAM ",key," ",sound.data.hex_encode().sha256_text()," ",sound.mix_rate," ",sound.stereo)
	print("AUDIO_PACK_PATHS failures=",failures);quit(1 if failures else 0)
