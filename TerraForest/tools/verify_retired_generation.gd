# SPDX-License-Identifier: 0BSD
extends SceneTree

func _initialize()->void:run.call_deferred()

func run()->void:
	var input:=""
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--retention-input="):input=argument.trim_prefix("--retention-input=")
	if input.is_empty():quit(2);return
	var request:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input))
	var verified:Array=[]
	var rejected:Array=[]
	for row:Dictionary in request.candidates:
		var source:String=request.root.path_join(row.stage+".trw")
		var target:String=request.root.path_join(row.destination+".trw")
		var source_hash:=FileAccess.get_sha256(source)
		var result:=verify_pair(source,target,row)
		if result.get("ok",false) and source_hash.length()==64 and source_hash==FileAccess.get_sha256(source):
			var entry:=row.duplicate();entry.source_sha256=source_hash;entry.destination_sha256=result.root_digest;verified.append(entry)
		else:rejected.append({"stage":row.stage,"destination":row.destination,"reason":result.get("reason","Working copy changed")})
		if (verified.size()+rejected.size())%10==0:print("GENERATION_RETENTION checked=",verified.size()+rejected.size())
		await process_frame
	var output:=FileAccess.open(input+".verified.json",FileAccess.WRITE)
	if output==null:quit(2);return
	output.store_string(JSON.stringify({"root":request.root,"verified":verified,"rejected":rejected},"  "));output.close()
	print("GENERATION_RETENTION verified=",verified.size()," retained=",rejected.size());quit()

static func verify_pair(source:String,target:String,row:Dictionary)->Dictionary:
	var options:Dictionary={}
	for key:String in row.options:
		var value:Variant=row.options[key]
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)!=float(int(value)):
			return {"ok":false,"reason":"Non-integral recipe option in publication receipt"}
		options[key]=int(value)
	var verifier=preload("res://addons/world_runtime/verify_generated_world.gd")
	var original:Dictionary=verifier.verify(source,int(row.seed),int(row.generator),options)
	if not original.get("ok",false):return {"ok":false,"reason":"Working copy: "+str(original.get("reason","Invalid"))}
	var result:Dictionary=verifier.verify(target,int(row.seed),int(row.generator),options)
	if not result.get("ok",false):return result
	if original.section_digests.get("world_recipe_v1","")!=result.section_digests.get("world_recipe_v1",""):
		return {"ok":false,"reason":"Saved recipes differ"}
	return result
