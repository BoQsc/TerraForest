# SPDX-License-Identifier: 0BSD
extends RefCounted
static func expand(path:String,payload:PackedByteArray)->PackedByteArray:
 if payload.size()<4 or payload.slice(0,4).get_string_from_ascii()!="TFTR":return payload
 var store=ClassDB.instantiate("NativeTerrainRegionStore")
 if not store.open_store(ProjectSettings.globalize_path(path)+".terrain"):return PackedByteArray()
 var bytes:PackedByteArray=store.expand_snapshot(payload);store.close();return bytes
static func cleanup(path:String)->void:
 # Only flat immutable files in this test's explicitly supplied sidecar.
 var folder:=ProjectSettings.globalize_path(path)+".terrain"
 for file:String in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(file))
 if DirAccess.dir_exists_absolute(folder):DirAccess.remove_absolute(folder)
