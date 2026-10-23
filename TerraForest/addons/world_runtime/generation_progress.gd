# SPDX-License-Identifier: 0BSD
extends RefCounted
# Stage observations only: never fabricate an overall completion percentage.
static func write(path:String,stage:String,completed:int=0,total:int=0)->bool:
 if path.is_empty() or completed<0 or total<0 or (total>0 and completed>total):return false
 var file:=FileAccess.open(path+".pending",FileAccess.WRITE)
 if file==null:return false
 file.store_string(JSON.stringify({"stage":stage,"completed":completed,"total":total}));file.close()
 return DirAccess.rename_absolute(path+".pending",path)==OK
static func read(path:String)->Dictionary:
 var file:=FileAccess.open(path,FileAccess.READ) if FileAccess.file_exists(path) else null
 if file==null or file.get_length()>4096:return {}
 var data=JSON.parse_string(file.get_as_text())
 if not data is Dictionary or not data.get("stage",null) is String:return {}
 var completed:=int(data.get("completed",-1));var total:=int(data.get("total",-1))
 if completed<0 or total<0 or completed>total or str(data.stage).length()>96:return {}
 return {"stage":data.stage,"completed":completed,"total":total}
