// SPDX-License-Identifier: 0BSD
#pragma once
#include <cmath>
#include <algorithm>
// Version 2 field primitives shared by the laboratory and immutable terrain 37.
// Inputs are metres; callers supply their deterministic signed noise field.
namespace terraforest::landforms::shapes {
inline float smooth(float x){x=std::clamp(x,0.f,1.f);return x*x*(3-2*x);}
template<class Noise> inline float lake(float ground,float distance,float width,float bank,float level,float depth,float variation,Noise noise){
 const float coves=variation*(.72f*noise(58,173)+.28f*noise(19,197));
 width*=1+coves;
 // Broad depositional shores alternate with steep rocky margins. A shallow
 // littoral shelf joins the deep basin with continuous height and derivative.
 float margin=smooth((noise(92,211)+.25f)*1.1f);
 float shore_bank=bank*(.40f+.60f*margin),q=distance/width;
 if(q>=1+shore_bank/width)return ground;
 float shelf=.60f+.20f*margin,submerged=std::min(depth,.75f+depth*.12f);
 float bed=q<shelf?level-depth+(depth-submerged)*smooth(q/shelf):level-submerged+submerged*smooth((q-shelf)/(1-shelf));
 if(q<=1)return bed;
 return level+(ground-level)*smooth((distance-width)/shore_bank);
}
template<class Noise> inline float ridge(float q,float depth,float variation,Noise noise){
 const float warp=1+variation*(noise(83,351)+.45f*noise(31,359));
 q/=warp;if(q>=1)return 0;
 float shoulder=smooth(1-q),crest=smooth(1-q*q);
 float dissection=.68f+.32f*(1-std::abs(noise(47,367)));
 float peaks=.78f+.35f*noise(119,373)+.14f*noise(38,379);
 return depth*(.28f*shoulder+.72f*crest)*dissection*peaks;
}
template<class Noise> inline float coast(float ground,float signed_distance,float bank,Noise noise,float sea){
 float shelf=bank*(.65f+.55f*smooth((noise(121,401)+.3f)*1.1f));
 float edge=signed_distance+5*noise(43,409)+1.4f*noise(13,419);
 float t=smooth((edge+shelf*.45f)/(shelf*1.9f));
 return (sea-12)*(1-t)+ground*t;
}
}
