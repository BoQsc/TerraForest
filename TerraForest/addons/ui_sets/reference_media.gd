# SPDX-License-Identifier: 0BSD
extends RefCounted
## Import-aware preview media access. Local report/user photographs are optional;
## no report folder or personal saved-world photograph is copied into a build.
static func texture(path:String)->Texture2D:
	var imported_ready:=true
	if FileAccess.file_exists(path+".import"):
		var import_settings:=ConfigFile.new()
		if import_settings.load(path+".import")==OK:
			var imported_path:String=import_settings.get_value("remap","path","")
			imported_ready=not imported_path.is_empty() and FileAccess.file_exists(imported_path)
	if imported_ready and path.begins_with("res://") and ResourceLoader.exists(path,"Texture2D"):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):return null
	var image:=Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(image) if image!=null else null
