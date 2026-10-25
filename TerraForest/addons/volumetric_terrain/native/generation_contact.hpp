#pragma once
#include "platform.h"
#include <cmath>
#include <initializer_list>

namespace terraforest::generation_contact {
constexpr double gap_limit=.10;
constexpr double burial_limit=.25;
constexpr double preferred_overlap=.08;
inline float smooth_unit(float fraction){return fraction*fraction*(3.f-2.f*fraction);}
inline float terrain_height(float original,float weight,bool embedded){
 float level=float(fl(original)),phase=original-level;
 const float overlap=float(preferred_overlap);
 float terrace=level+overlap+smooth_unit(clampf((phase-.25f)/.5f,0.f,1.f));
 if(embedded)terrace=level+overlap+smooth_unit(clampf((phase-.35f)/.3f,0.f,1.f));
 float adjusted=original+(terrace-original)*weight;
 if(embedded){
  float contact=float(fl(adjusted+.5f))+overlap,correction=contact-adjusted;
  float influence=smooth_unit(clampf((.30f-ab(correction))/.15f,0.f,1.f))*smooth_unit(clampf(weight/.2f,0.f,1.f));
  adjusted+=correction*influence;
 }
 return adjusted;
}
inline bool fits(double minimum,double maximum){return std::ceil(maximum-burial_limit-1e-5)<=std::floor(minimum+gap_limit+1e-5);}
struct Penalty {double cost=0,lower_gradient=0,upper_gradient=0,base=0;};
inline Penalty penalty(double minimum,double maximum,double allowed_gap=gap_limit,double allowed_burial=burial_limit){
 Penalty best;best.cost=1e30;
 double lower=std::floor((minimum+maximum)*.5);
 for(double base:{lower,lower+1}){
  double gap=base-minimum-allowed_gap,burial=maximum-base-allowed_burial;
  gap=gap>0?gap:0;burial=burial>0?burial:0;
  double cost=gap*gap+burial*burial;
  if(cost<best.cost)best={cost,-2*gap,2*burial,base};
 }
 return best;
}
inline double preferred_height(double original){return std::floor(original+.5-preferred_overlap)+preferred_overlap;}
}
