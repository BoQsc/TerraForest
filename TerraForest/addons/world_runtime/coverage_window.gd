# SPDX-License-Identifier: 0BSD
extends RefCounted
# Startup-only readiness query over the existing 64 m landscape owner grid.
# Distant owner generation continues; unknown local owners never count as empty.
static func intersects(point:Vector3,radius:float,key:Vector2i)->bool:
 var dx:=maxf(maxf(key.x*64.0-point.x,point.x-(key.x+1)*64.0),0)
 var dz:=maxf(maxf(key.y*64.0-point.z,point.z-(key.y+1)*64.0),0)
 return dx*dx+dz*dz<=radius*radius

static func required(point:Vector3,radius:float,key:Vector2i)->bool:
 # With no local owners, readiness falls back to whole-world coverage.
 var dx:=maxf(maxf(-point.x,point.x-2048.0),0)
 var dz:=maxf(maxf(-point.z,point.z-2048.0),0)
 return dx*dx+dz*dz>radius*radius or intersects(point,radius,key)

static func inspect(point:Vector3,radius:float,present:Dictionary,pending:Array[Dictionary])->Dictionary:
 var total:=0;var ready:=0
 var first:=Vector2i(maxi(0,floori((point.x-radius)/64)-1),maxi(0,floori((point.z-radius)/64)-1))
 var last:=Vector2i(mini(31,floori((point.x+radius)/64)),mini(31,floori((point.z+radius)/64)))
 for z in range(first.y,last.y+1):
  for x in range(first.x,last.x+1):
   var key:=Vector2i(x,z)
   if not intersects(point,radius,key):continue
   total+=1
   if not present.has(key):continue
   var available:=true
   for queue:Dictionary in pending:
    if queue.has(key):available=false;break
   if available:ready+=1
 return {"ready":total>0 and ready==total,"owners":ready,"total":total,"radius":radius,"scope":"local landscape"}
