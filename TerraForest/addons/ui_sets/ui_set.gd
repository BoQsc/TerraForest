# SPDX-License-Identifier: 0BSD
extends Resource
## One discoverable presentation package. World state/actions stay in their hosts.
@export var schema:=1
@export var id:=""
@export var title:=""
@export_multiline var description:=""
@export var base:Resource
@export var preview:PackedScene
@export var preview_pages:=PackedStringArray()
@export var preview_size:=Vector2i(1920,1080)
@export var runtime_preview:PackedScene
@export var runtime_preview_pages:=PackedStringArray()
@export var runtime_enabled:=false
@export var browser_view:Script
@export var creation_view:Script
@export var loading_panel:Script
@export var loading_background:Script
@export var loading_details:Script
@export var accent:=Color("91d5b4")
@export var background:=Color("0b171d")
@export var panel_color:=Color("14292e")
@export var heading_font:Font
@export var body_font:Font
