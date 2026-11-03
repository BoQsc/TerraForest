# SPDX-License-Identifier: 0BSD
extends RefCounted
## Shared modal-window close contract.
## Esc and Tab both close the active window.
## Callers handle non-standard keys (such as E) themselves.

static func is_close_key(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE,KEY_TAB]

static func close_window(owner: Node,event: InputEvent,close_action: Callable) -> bool:
	if not is_close_key(event):return false
	close_action.call()
	owner.get_viewport().set_input_as_handled()
	return true
