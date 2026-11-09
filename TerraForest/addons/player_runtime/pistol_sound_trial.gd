# SPDX-License-Identifier: 0BSD
extends Node3D
## User-selected trial pair; original recordings remain selectable at runtime.
const TRIAL_GAIN_DB=-4.0
const SHOT=preload("res://addons/audio_runtime/packs/happysoul_px9_trial/shot.mp3")
const RELOAD=preload("res://addons/audio_runtime/packs/happysoul_px9_trial/reload.mp3")
var use_original:=false
var settings_path:String=ProjectSettings.get_setting("terraforest/px9_audio_settings_path","user://px9_audio.cfg")
var follow_target:Node3D
var reload_voice:AudioStreamPlayer3D
signal mode_changed(original:bool)
func _ready()->void:
    if settings_path.is_empty():return
    var config:=ConfigFile.new()
    if config.load(settings_path)==OK:use_original=config.get_value("pistol","original",false)==true
func set_original(value:bool)->void:
    if use_original==value:return
    use_original=value;stop_reload()
    if not settings_path.is_empty():
        var config:=ConfigFile.new();config.set_value("pistol","original",value);config.save(settings_path)
    mode_changed.emit(value)
func shot(previous:AudioStream)->AudioStream:return previous if use_original else SHOT
func start_reload(point:Vector3)->void:
    stop_reload()
    if use_original:return # Legacy magazine-out cue remains in the host.
    _play_reload(RELOAD,TRIAL_GAIN_DB,point)
func original_reload(previous:AudioStream,point:Vector3)->void:
    if use_original:_play_reload(previous,0.0,point)
func _play_reload(stream:AudioStream,gain_db:float,point:Vector3)->void:
    if not is_instance_valid(reload_voice):
        reload_voice=AudioStreamPlayer3D.new();reload_voice.name="PX9ReloadAudio"
        reload_voice.max_distance=24;reload_voice.bus="TerraForestEffects"
        # The eye is part of the physical player, even in third-person view.
        # Parenting keeps mechanical audio at the player without a follow tick.
        var source_parent:Node3D=follow_target if is_instance_valid(follow_target) else self
        source_parent.add_child(reload_voice)
    if is_instance_valid(follow_target):reload_voice.position=Vector3.ZERO
    else:reload_voice.global_position=point
    reload_voice.volume_db=gain_db;reload_voice.stream=stream;reload_voice.play()
func stop_reload()->void:
    if is_instance_valid(reload_voice):reload_voice.stop()
func _exit_tree()->void:
    # The emitter can live under the camera, outside this helper's own subtree.
    if is_instance_valid(reload_voice):reload_voice.stop();reload_voice.queue_free()
