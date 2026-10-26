// SPDX-License-Identifier: 0BSD
#pragma once
#include "platform.h"
// One seed-derived capsule per 32 m cell; influence vanishes before boundaries.
// Continuous signed weight: iron positive, copper negative. Stable IDs: 8 and 9.
struct GeologicalVein {V3 start,end;float radius;u8 material;};
inline GeologicalVein geological_vein(int column,int level,int row,u32 seed){
 u32 first=hash32(u32(column)*73856093u^u32(level)*83492791u^u32(row)*19349663u^seed^0xa5317bcdu),second=hash32(first);
 V3 origin={float(column*32),float(level*32),float(row*32)};
 return {origin+V3{8.f+float(first&7),8.f+float((first>>3)&7),8.f+float((first>>6)&7)},
  origin+V3{18.f+float(second&7),18.f+float((second>>3)&7),18.f+float((second>>6)&7)},
  2.f+float((first>>12)&3)*.5f,u8((first&0x80000000u)?9:8)};
}
inline float geological_weight(V3 point,float surface,u32 seed) {
 if(point.y<4||surface-point.y<6)return 0;
 auto vein=geological_vein(fl(point.x/32),fl(point.y/32),fl(point.z/32),seed);
 V3 axis=vein.end-vein.start;float along=clampf(dot(point-vein.start,axis)/mx(dot(axis,axis),.001f),0,1);
 float amount=clampf(vein.radius+.75f-length(point-vein.start-axis*along),0,1)*clampf((surface-point.y-6.f)*.5f,0,1);
 return vein.material==9?-amount:amount;
}
