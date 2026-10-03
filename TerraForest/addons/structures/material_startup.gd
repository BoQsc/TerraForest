# SPDX-License-Identifier: 0BSD
extends RefCounted
static func prepare(blocks: Node) -> bool:
	# Initialize textures/mipmaps before interactive mesh publication. Match the
	# native initial selection policy, including the command-line override.
	var selected: String=str(ProjectSettings.get_setting("structures/material_set","original"))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--block-textures="): selected=argument.get_slice("=",1)
	return blocks.set_texture_set(selected) or blocks.set_texture_set("original")
