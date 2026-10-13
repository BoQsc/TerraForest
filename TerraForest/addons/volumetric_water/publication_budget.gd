# SPDX-License-Identifier: 0BSD
extends RefCounted
# Keep upload frequency bounded; raising this alone multiplies repeated meshes.
const MAX_PACKETS:=4
const SOFT_TIME_US:=1000
