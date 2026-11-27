# SPDX-License-Identifier: 0BSD
extends RefCounted
## Scene/worker bridge; all binary validation and store traversal are native.
static func verify(path:String,seed_value:int,generator:int,options:Dictionary={})->Dictionary:
 var verifier:RefCounted=ClassDB.instantiate("NativeGeneratedWorldVerifier")
 return verifier.verify(path,seed_value,generator,options)
