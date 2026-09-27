// SPDX-License-Identifier: 0BSD
#pragma once
#include "platform.h"

struct PrimitiveStamp {
 // Versioned command 17: sphere, box, vertical cylinder, slope, stairs.
 u32 shape=0,turn=0,steps=1,add=1,material=1;
 V3 center,half;
 static float box(V3 p,V3 h){V3 q{ab(p.x)-h.x,ab(p.y)-h.y,ab(p.z)-h.z};return length({mx(q.x,0),mx(q.y,0),mx(q.z,0)})+mn(mx(q.x,mx(q.y,q.z)),0);}
 V3 extent()const{return turn&1?V3{half.z,half.y,half.x}:half;}
 bool valid()const{
  if(shape>4||turn>3||add>1||material<1||material>3)return false;
  if(!(__builtin_isfinite(center.x)&&__builtin_isfinite(center.y)&&__builtin_isfinite(center.z)))return false;
  if(!(half.x>=.5f&&half.x<=32&&half.y>=.5f&&half.y<=32&&half.z>=.5f&&half.z<=32))return false;
  if(shape==0&&(half.x!=half.y||half.x!=half.z))return false;
  if(shape==2&&half.x!=half.z)return false;
  if(shape==4){if(steps<2||steps>16||2*half.y<steps||2*half.z<steps)return false;}
  else if(steps!=1)return false;
  const V3 e=extent(),lo=center-e,hi=center+e;
  if(lo.x<1||lo.y<4||lo.z<1||hi.x>1999||hi.y>254||hi.z>1999)return false;
  // Conservative lattice-work bound, including reconstruction support.
  const u64 work=u64(2*e.x+12)*u64(2*e.y+12)*u64(2*e.z+12)*(shape==4?steps:1);
  return work<=2000000;
 }
 float distance(V3 point)const{
  V3 p=point-center;
  if(turn==1)p={-p.z,p.y,p.x};else if(turn==2)p={-p.x,p.y,-p.z};else if(turn==3)p={p.z,p.y,-p.x};
  if(shape==0)return length(p)-half.x;
  if(shape==1)return box(p,half);
  if(shape==2){float r=root(p.x*p.x+p.z*p.z)-half.x,y=ab(p.y)-half.y;return root(mx(r,0)*mx(r,0)+mx(y,0)*mx(y,0))+mn(mx(r,y),0);}
  if(shape==3){float slope=half.y/half.z;return mx(box(p,half),(p.y-slope*p.z)/root(1+slope*slope));}
  float result=1e20f;
  // Nested boxes overlap below every riser: no zero-distance interior seams.
  for(u32 i=0;i<steps;i++){
   float start=-half.z+2*half.z*i/steps,hy=half.y*(i+1)/steps,hz=(half.z-start)*.5f;
   V3 c{0,-half.y+hy,start+hz};
   result=mn(result,box(p-c,{half.x,hy,hz}));
  }
  return result;
 }
 bool decode(const u8 *data,int size){
  if(size!=52)return false;
  Reader r{data,size};if(r.u()!=17||r.u()!=1)return false;
  shape=r.u();center=r.vec();half=r.vec();turn=r.u();steps=r.u();add=r.u();material=r.u();
  return r.good&&valid();
 }
 void encode(Bytes &data)const{data.u(17);data.u(1);data.u(shape);data.vec(center);data.vec(half);data.u(turn);data.u(steps);data.u(add);data.u(material);}
};
