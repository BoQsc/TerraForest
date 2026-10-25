extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Baseline:="res://docs/evidence/generation_contact_native/legacy_heights.bin"
var failures:=0
func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->void:
	print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
func survey(core:RefCounted,points:PackedVector3Array)->PackedByteArray:
	var values:=PackedByteArray()
	for first in range(0,points.size(),256):
		var batch:=points.slice(first,mini(first+256,points.size()));var request:=Codec.command(37,[batch.size()]);request.append_array(batch.to_byte_array())
		var reply:PackedByteArray=core.execute(request)
		if not Codec.reply_ok(reply):return PackedByteArray()
		values.append_array(reply.slice(12))
	return values
func run()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var capture:bool="--capture-legacy" in OS.get_cmdline_user_args()
	var points:=PackedVector3Array()
	for across in range(32,2000,97):
		for along in range(32,2000,103):points.append(Vector3(across+.37,0,along+.61))
	var results:Dictionary={};var started:=Time.get_ticks_usec()
	for seed_value in [42,1703,9137]:
		for generator in [20,21,22,23]:
			var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,generator]))
			results["%d/%d"%[seed_value,generator]]=survey(core,points)
	if capture:
		if FileAccess.file_exists(Baseline):push_error("Refusing to replace legacy evidence");quit(2);return
		DirAccess.make_dir_recursive_absolute(Baseline.get_base_dir());FileAccess.open(Baseline,FileAccess.WRITE).store_var(results)
		print("GENERATION_CONTACT_LEGACY_CAPTURED");quit();return
	var expected:Dictionary=FileAccess.open(Baseline,FileAccess.READ).get_var()
	check(results==expected,"all legacy height/material bytes remain identical across twelve profiles/seeds")
	DirAccess.make_dir_recursive_absolute("res://reports")
	FileAccess.open("res://reports/generation_contact_policy.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"legacy_cases":results.size(),"points_per_case":points.size(),"milliseconds":(Time.get_ticks_usec()-started)/1000.0},"  "))
	print("GENERATION_CONTACT_POLICY failures=",failures);quit(1 if failures else 0)
