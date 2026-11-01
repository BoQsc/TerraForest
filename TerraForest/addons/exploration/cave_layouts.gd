# SPDX-License-Identifier: 0BSD
extends RefCounted

const PATH:="res://addons/exploration/small_locations.poi.json"

static func load_catalog(path:String=PATH)->Array:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>65536:return reject("Missing/oversized catalog: "+path)
	var parsed=JSON.parse_string(file.get_buffer(file.get_length()).get_string_from_utf8())
	if not parsed is Dictionary or parsed.get("version")!=1 or not parsed.get("layouts") is Array:return reject("Invalid catalog version/structure")
	if parsed.layouts.is_empty() or parsed.layouts.size()>8:return reject("Expected one to eight layouts")
	var result:Array=[];var identities:Dictionary={}
	for entry in parsed.layouts:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("title") is String:return reject("Missing layout identity/title")
		if entry.id.is_empty() or not entry.id.is_valid_identifier() or entry.id.length()>48 or identities.has(entry.id) or entry.title.length()>96:return reject("Invalid/duplicate layout identity")
		identities[entry.id]=true
		var layout:Dictionary={"id":entry.id,"title":entry.title,"tunnels":[],"entrance_cuts":[],"frames":[],"crates":[],"sleepers":[],"views":[]}
		var entrances=entry.get("entrance_cuts",[])
		if not entrances is Array or entrances.size()>4:return reject(entry.id+": excessive entrance cuts")
		for recess in entrances:
			if not recess is Array or not numbers(recess,5):return reject(entry.id+": invalid entrance cut")
			if absf(recess[0])>4 or recess[1]<-4 or recess[1]>0 or recess[2]<1 or recess[2]>7 or recess[3]<1 or recess[3]>4 or recess[4]<8 or recess[4]>12:return reject(entry.id+": entrance cut outside authoring bounds")
			layout.entrance_cuts.append(recess.duplicate())
		if not entry.get("tunnels") is Array or entry.tunnels.size()<2 or entry.tunnels.size()>16:return reject(entry.id+": expected two to sixteen tunnels")
		for tunnel in entry.tunnels:
			if not tunnel is Array or tunnel.size()!=4 or not numbers(tunnel[0],3) or not numbers(tunnel[1],3) or not numbers(tunnel.slice(2),2):return reject(entry.id+": invalid tunnel record "+str(tunnel))
			var start:=point(tunnel[0]);var finish:=point(tunnel[1]);var width:float=tunnel[2];var height:float=tunnel[3]
			if width<1.5 or width>8 or height<width or height>minf(12,width*1.75) or start.y!=0 or finish.y!=0 or start.distance_to(finish)<1 or start.distance_to(finish)>64:return reject(entry.id+": unsupported tunnel dimensions "+str(tunnel))
			layout.tunnels.append({"start":start,"finish":finish,"half_width":width,"clearance":height})
		for group:String in ["frames","crates","sleepers","views"]:
			var count:=5 if group=="sleepers" else 6 if group=="views" else 4
			if not entry.get(group) is Array or entry[group].size()>16:return reject(entry.id+": invalid "+group+" list")
			if group=="crates" and entry[group].is_empty():return reject(entry.id+": missing supplies")
			for item in entry[group]:
				if not numbers(item,count):return reject(entry.id+": invalid "+group+" record")
				if group!="views" and item[1]!=0:return reject(entry.id+": expected floor-level "+group)
				if group=="frames" and (item[0]!=int(item[0]) or item[2]!=int(item[2]) or item[3]!=int(item[3]) or item[3]<0 or item[3]>3):return reject(entry.id+": frame is not grid-aligned")
				if group=="sleepers" and (item[4]!=int(item[4]) or int(item[4]) not in [1,2]):return reject(entry.id+": unsupported sleep pose")
				layout[group].append(item)
		result.append(layout)
	return result

static func reject(reason:String)->Array:
	push_warning("Invalid exploration layout: "+reason)
	return []

static func numbers(value:Variant,count:int)->bool:
	if not value is Array or value.size()!=count:return false
	for number in value:
		if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(number) or absf(number)>64:return false
	return true

static func point(values:Array)->Vector3:
	return Vector3(values[0],values[1],values[2])

static func turn(position:Vector3,rotation:int)->Vector3:
	for quarter in posmod(rotation,4):position=Vector3(1-position.z,position.y,position.x)
	return position

static func segments(layout:Dictionary,origin:Vector3i,rotation:int)->Array:
	var result:Array=[]
	for tunnel:Dictionary in layout.tunnels:
		var start:=Vector3(origin)+turn(tunnel.start,rotation);var finish:=Vector3(origin)+turn(tunnel.finish,rotation)
		var width:float=tunnel.half_width;var height:float=tunnel.clearance
		var lower:=start.min(finish)-Vector3(width,1,width);var upper:=start.max(finish)+Vector3(width,height,width)
		result.append({"start":start,"finish":finish,"half_width":width,"depth":1.0,"clearance":height,"material":1,"shoulder":0.0,"arched":true,"cut_only":true,"phase":"excavation","bounds":AABB(lower,upper-lower)})
	for recess:Array in layout.get("entrance_cuts",[]):
		var start:=Vector3(origin)+turn(Vector3(recess[0],0,recess[1]),rotation);var finish:=Vector3(origin)+turn(Vector3(recess[0],0,recess[2]),rotation)
		var width:float=recess[3];var height:float=recess[4]
		var lower:=start.min(finish)-Vector3(width,1,width);var upper:=start.max(finish)+Vector3(width,height,width)
		result.append({"start":start,"finish":finish,"half_width":width,"depth":1.0,"clearance":height,"material":1,"shoulder":0.0,"rectangular":true,"cut_only":true,"phase":"excavation","bounds":AABB(lower,upper-lower)})
	return result

static func prefab(layout:Dictionary)->Resource:
	var encoder=ClassDB.instantiate("NativeBlockWorld")
	var cells:Dictionary={}
	for frame:Array in layout.frames:
		var local:Array=[]
		for side in [-2,2]:
			for level in 3:local.append([Vector3i(side,level,0),5])
		for column in range(-2,3):local.append([Vector3i(column,3,0),2])
		for part:Array in local:
			var position:Vector3i=part[0]
			for quarter in int(frame[3]):position=Vector3i(-position.z,position.y,position.x)
			position+=Vector3i(frame[0],frame[1],frame[2])
			cells[position]=encoder.encode_block(part[1],int(frame[3]),1,3)
	if layout.id=="coal_mine":preload("res://addons/exploration/coal_mine.gd").add_cells(cells,encoder)
	encoder.free()
	var records:=PackedInt32Array()
	for position:Vector3i in cells:records.append_array(PackedInt32Array([position.x,position.y,position.z,cells[position]]))
	var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
	if not asset.configure(records):return null
	var attachments:Array=[]
	for crate:Array in layout.crates:attachments.append({"model":"storage/wooden_chest/v1","transform":Transform3D(Basis(Vector3.UP,crate[3]),point(crate))})
	if layout.id=="coal_mine":attachments.append_array(preload("res://addons/exploration/coal_mine.gd").attachments())
	if not asset.configure_model_attachments(attachments):return null
	var envelope:=AABB();var has_envelope:=false
	var crate_mesh:Mesh=load("res://addons/structures/prefabs/storage_chest_model.tres")
	for attachment:Dictionary in attachments:
		var mesh:Mesh=crate_mesh if attachment.model=="storage/wooden_chest/v1" else preload("res://addons/exploration/coal_mine.gd").mesh_for(attachment.model)
		if mesh==null:return null
		var bounds:AABB=attachment.transform*mesh.get_aabb()
		envelope=envelope.merge(bounds) if has_envelope else bounds;has_envelope=true
	if has_envelope and not asset.configure_attachment_envelope(envelope.grow(.01)):return null
	asset.resource_name=layout.title;asset.set_meta("exploration_id",layout.id)
	return asset

static func sleepers(layout:Dictionary,origin:Vector3i,rotation:int)->Array:
	var result:Array=[]
	for slot in layout.sleepers.size():
		var sleeper:Array=layout.sleepers[slot]
		var identity:int=(1<<40)|(origin.x+1)|((origin.z+1)<<11)|(rotation<<22)|((slot+1)<<24)|(origin.y<<29)
		if layout.id=="coal_mine":identity|=(1<<42)|((1<<43) if slot>=3 else 0)
		result.append({"key":identity,"position":Vector3(origin)+turn(point(sleeper),rotation)+Vector3(0,.002,0),"yaw":sleeper[3]-rotation*PI*.5,"pose":int(sleeper[4])})
	return result
