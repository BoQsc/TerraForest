# SPDX-License-Identifier: 0BSD
extends RefCounted
# Main-thread request identities shared by all surface sampling clients.
static var _next: int=1
static func allocate() -> int:
	var result:=_next
	_next+=1
	return result
