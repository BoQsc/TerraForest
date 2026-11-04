# SPDX-License-Identifier: 0BSD
extends RefCounted
## Shared keyboard-input rule for editable text controls.

static func owns(viewport: Viewport) -> bool:
	var focused := viewport.gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

static func configure(control: Control) -> void:
	control.focus_mode = Control.FOCUS_ALL
	control.mouse_filter = Control.MOUSE_FILTER_STOP
