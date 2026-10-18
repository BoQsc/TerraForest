# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline composition choices; native prefabs own geometry and runtime batching.
static func plan(site:int)->Dictionary:
 var cottage:="Furnished cottage with door and windows"
 var tower:="Furnished tower · 3 floors"
 match site:
  1:return {"title":"Western residential lane","sources":[cottage],"lots":2,"streets":1,"width":6,"gap":4,"buildings":4}
  2:return {"title":"Eastern mine service street","sources":[cottage],"lots":1,"streets":1,"width":8,"gap":4,"buildings":2}
  3:return {"title":"Northern multi-storey district","sources":[tower],"lots":2,"streets":1,"width":10,"gap":5,"buildings":4}
  4:return {"title":"Southern broad residential lane","sources":[cottage],"lots":2,"streets":1,"width":12,"gap":8,"buildings":4}
 return {}
