# SPDX-License-Identifier: 0BSD
extends Node3D
## Reuses existing Kaino recordings; a separate bounded pool cannot steal gunshots.
const BASE="res://addons/audio_runtime/packs/Kaino/1/"
const FILES={"stone":["Stone Thud 1 - Kaino.wav","Stone Thud 2 - Kaino.wav"],"wood":["split/Chopping Wood 2 - Kaino_hit1.wav","split/Chopping Wood 2 - Kaino_hit2.wav"],"metal":["Metal Clang 1 - Kaino.wav","Metal Clang 2 - Kaino.wav"],"flesh":["Punch 1 - Kaino.wav","Punch 2 - Kaino.wav"]}
var streams:Dictionary={}
var pool:Array[AudioStreamPlayer3D]=[]
var random:=RandomNumberGenerator.new()
var played:=0
var last_material:=""
func _ready()->void:
    random.randomize()
    var decoder=preload("res://addons/audio_runtime/wav_decoder.gd")
    for material:String in FILES:
        streams[material]=[]
        for file:String in FILES[material]:
            var sound:AudioStreamWAV=decoder.decode(BASE+file)
            if sound!=null:streams[material].append(sound)
func impact(point:Vector3,material:String)->void:
    if not point.is_finite():return
    var key:String=material if material in FILES else ("wood" if material=="foliage" else "stone")
    if streams.get(key,[]).is_empty():return
    var voice:AudioStreamPlayer3D
    for candidate in pool:
        if not candidate.playing:voice=candidate;break
    if voice==null:
        if pool.size()>=8:return
        voice=AudioStreamPlayer3D.new();voice.bus="TerraForestEffects";voice.max_distance=36;voice.unit_size=3;voice.attenuation_filter_cutoff_hz=6500
        add_child(voice);pool.append(voice)
    voice.stream=streams[key][random.randi_range(0,streams[key].size()-1)]
    voice.volume_db={"stone":-15.0,"wood":-12.0,"metal":-17.0,"flesh":-17.0}[key]
    voice.pitch_scale=random.randf_range(.96,1.07);voice.global_position=point;voice.play()
    played+=1;last_material=material
func clear()->void:
    for voice in pool:voice.stop()
