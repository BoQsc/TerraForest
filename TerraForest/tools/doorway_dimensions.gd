# SPDX-License-Identifier: 0BSD
extends RefCounted
## Authoring-only repair. Never mutates a saved world or player construction.
const KEY="architecture/wooden_door/v1"
const SCALE_Y:=2.0/2.2
static func normalize(asset:Resource,blocks:Node)->int:
	var records:PackedInt32Array=asset.get_records()
	var cells:={}
	for i in range(0,records.size(),4):cells[Vector3i(records[i],records[i+1],records[i+2])]=records[i+3]
	var attachments:Array=asset.get_model_attachments()
	var changed:=0
	for row:Dictionary in attachments:
		if row.model!=KEY:continue
		var pose:Transform3D=row.transform
		var previous:=pose.basis.y.length()
		if is_equal_approx(previous,SCALE_Y):continue
		# Close only the extra row of an originally oversized doorway. Keep the
		# surrounding wall's material/appearance, including reversed double leaves.
		if previous*2.2>2.1:
			var center:=pose*Vector3(.5,0,0)
			var lintel:=Vector3i(floori(center.x),roundi(center.y)+2,floori(center.z))
			if not cells.has(lintel):
				var word:int=cells.get(lintel+Vector3i.UP,0)
				if word==0:
					for offset in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
						word=cells.get(lintel+offset,0)
						if word!=0:break
				var decoded:Dictionary=blocks.decode_block(word)
				if decoded.is_empty():push_error("Missing wall material above door in "+asset.resource_path);return -1
				var full:int=blocks.encode_block(1,0,decoded.material,decoded.appearance)
				cells[lintel]=full;records.append_array(PackedInt32Array([lintel.x,lintel.y,lintel.z,full]))
		pose.basis.y=pose.basis.y.normalized()*SCALE_Y
		row.transform=pose;changed+=1
	if changed>0:
		if not asset.configure(records) or not asset.configure_model_attachments(attachments):return -1
		asset.set_meta("doorway_height_m",2.0)
	return changed
