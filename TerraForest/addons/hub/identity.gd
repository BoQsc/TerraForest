# SPDX-License-Identifier: 0BSD
extends RefCounted
## Anonymous player identity for the hub: a local nickname + tag, no accounts.
##
## Stored in user://hub/identity.json so the same name survives restarts. There
## is no keyserver and no Steam dependency; a reinstall simply gets a new name.
const PATH:="user://hub/identity.json"
const ADJECTIVES:=["amber","birch","cedar","dusk","ember","fen","grove","hazel","ivy","juniper","kelp","larch","moss","nettle","oak","pine","quill","reed","spruce","thorn","umber","vine","willow","yew"]
const NOUNS:=["badger","crane","doe","eagle","finch","hare","ibis","jay","kite","lynx","marten","otter","puffin","quail","raven","swan","tern","vole","wren","yak"]
## A second local name for tests or for a player running two copies at once,
## so both instances are visible as different peers in the same room.
static func clone(identity:Dictionary)->Dictionary:
	var copy:=identity.duplicate()
	copy["nickname"]="%s-%02d"%[str(identity.get("nickname","player")),randi_range(10,99)]
	copy["tag"]=randi_range(1000,9999)
	return copy
static func generate()->Dictionary:
	var adjective:String=ADJECTIVES.pick_random()
	var noun:String=NOUNS.pick_random()
	return {"nickname":"%s-%s-%02d" % [adjective,noun,randi_range(0,99)],"tag":randi_range(1000,9999),"created":int(Time.get_unix_time_from_system())}
static func load_or_create()->Dictionary:
	if FileAccess.file_exists(PATH):
		var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary and not str(parsed.get("nickname","")).is_empty():return parsed
	var identity:=generate()
	save(identity)
	return identity
static func save(identity:Dictionary)->bool:
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var file:=FileAccess.open(PATH,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(identity))
	file.close()
	return true
## Display name sent to the room: nickname plus tag, e.g. "moss-otter#42".
static func display(identity:Dictionary)->String:
	var clean:=clean_nickname(str(identity.get("nickname","")))
	var tag:=int(identity.get("tag",0))
	if clean.is_empty():
		if tag<=0:return "anonymous"
		clean="anonymous"
	if tag<=0:return clean
	return "%s#%d" % [clean,tag]
## User-edited nickname: printable, single line, at most 24 characters.
static func clean_nickname(value:String)->String:
	var out:=""
	var source:=value.replace("\n"," ").replace("\r"," ").replace("\t"," ").replace("["," ").replace("]"," ")
	for i:int in source.length():
		if out.length()>=24:break
		var code:=source.unicode_at(i)
		if code>=32 and code!=127:out+=source[i]
	return out.strip_edges()
