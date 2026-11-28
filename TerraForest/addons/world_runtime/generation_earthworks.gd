# SPDX-License-Identifier: 0BSD
extends RefCounted
# JSON/Variant authoring enters once; ordering and binary packet encoding are native.
static func packets(segments:Array,deposits:Array=[])->Array:
 return ClassDB.instantiate("NativeGenerationEarthworks").compile(segments,deposits)
static func ordered_segments(segments:Array)->Array:
 return ClassDB.instantiate("NativeGenerationEarthworks").ordered(segments)
static func curve_prefix(segment:Dictionary)->PackedFloat64Array:
 return ClassDB.instantiate("NativeGenerationEarthworks").curve_prefix(segment)
