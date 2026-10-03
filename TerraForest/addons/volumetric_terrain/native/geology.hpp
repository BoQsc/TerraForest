// SPDX-License-Identifier: 0BSD
#pragma once
#include "platform.h"
// One seed-derived capsule per 32 m cell; influence vanishes before boundaries.
// Continuous signed weight: iron positive, copper negative. Stable IDs: 8 and 9.
inline float geological_weight(V3 p,float surface,u32 seed) {
 if(p.y<4||surface-p.y<6)return 0;
 int x=fl(p.x/32),y=fl(p.y/32),z=fl(p.z/32);
 u32 h=hash32(u32(x)*73856093u^u32(y)*83492791u^u32(z)*19349663u^seed^0xa5317bcdu),k=hash32(h);
 V3 origin={float(x*32),float(y*32),float(z*32)};
 V3 a=origin+V3{8.f+float(h&7),8.f+float((h>>3)&7),8.f+float((h>>6)&7)};
 V3 b=origin+V3{18.f+float(k&7),18.f+float((k>>3)&7),18.f+float((k>>6)&7)};
 V3 axis=b-a;float t=clampf(dot(p-a,axis)/mx(dot(axis,axis),.001f),0,1);
 float radius=2.f+float((h>>12)&3)*.5f;
 float amount=clampf(radius+.75f-length(p-a-axis*t),0,1)*clampf((surface-p.y-6.f)*.5f,0,1);
 return (h&0x80000000u)?-amount:amount;
}
