# SPDX-License-Identifier: 0BSD
extends RefCounted
## Forge project identity for the community hub.
##
## The public project id is safe to ship: it addresses realtime rooms and the
## public site files (`/<id>/...`). The secret key (`fsk_...`) must never be
## committed or exported; it is only needed to publish news.json / issues.json.
const BASE:="https://forge.boqsc.eu"
const PROJECT_ID:="fg_7d1ddfd4506e8593"
const USER_AGENT:="TerraForest-Hub/1.0 (Godot)"
const ROOM_GENERAL:="tf/general"
const ROOM_LIMIT:=60
const ALLOWED:="abcdefghijklmnopqrstuvwxyz0123456789-_"
## Room for a saved world slot: lowercase, only room-safe characters.
static func room_for_world(slot:String)->String:
	var clean:=slot.strip_edges().to_lower()
	var out:=""
	for i:int in clean.length():
		var piece:=clean[i]
		out+=piece if ALLOWED.contains(piece) else "-"
	out=out.trim_prefix("-").trim_suffix("-")
	if out.is_empty():return "tf/world/unnamed"
	return "tf/world/"+out.substr(0,40)
static func public_url(path:String)->String:
	return "%s/~/%s/%s" % [BASE,PROJECT_ID,path.trim_prefix("/")]
static func host()->String:
	return BASE.replace("https://","").replace("http://","")
