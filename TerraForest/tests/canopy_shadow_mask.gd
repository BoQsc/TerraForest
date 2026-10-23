# SPDX-License-Identifier: 0BSD
extends SceneTree
const Forest=preload("res://addons/vegetation/forest.gd")
func _initialize():
 var forest=Forest.new();var failures:=0
 var native=forest.native_selection
 forest.roots={1:{"t":Transform3D(Basis.IDENTITY,Vector3(32,0,32))}}
 var sun=Vector3(-.35,.75,.55).normalized()
 var mask:PackedByteArray=native.shadow_mask(forest,Vector3.ZERO,64,64,sun)
 var nonzero:=0
 for v in mask:nonzero+=int(v>0)
 if mask.size()!=4096 or nonzero<10 or nonzero>200:failures+=1
 if mask!=native.shadow_mask(forest,Vector3.ZERO,64,64,sun):failures+=1
 if not native.prepare_shadow_mask(forest,Vector3.ZERO,64,64,sun):failures+=1
 forest.roots.clear()
 var worker:=Thread.new();worker.start(native.build_shadow_mask)
 var captured:PackedByteArray=worker.wait_to_finish()
 if captured!=mask:failures+=1
 var empty:PackedByteArray=native.shadow_mask(forest,Vector3.ZERO,64,64,sun)
 for value in empty:
  if value!=0:failures+=1;break
 if not native.shadow_mask(forest,Vector3.ZERO,64,512,sun).is_empty():failures+=1
 if not native.shadow_mask(forest,Vector3.ZERO,64,64,Vector3.ZERO).is_empty():failures+=1
 for i in 16384:forest.roots[i]={"t":Transform3D(Basis.IDENTITY,Vector3((i%128)*8,0,(i/128)*8))}
 var begun=Time.get_ticks_usec()
 mask=native.shadow_mask(forest,Vector3.ZERO,1024,256,sun)
 print("CANOPY_MASK roots=16384 bytes=",mask.size()," native_us=",Time.get_ticks_usec()-begun)
 if mask.size()!=65536:failures+=1
 forest.free();print("CANOPY_SHADOW_MASK failures=",failures);quit(1 if failures else 0)
