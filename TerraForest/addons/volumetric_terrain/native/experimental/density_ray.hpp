// SPDX-License-Identifier: 0BSD
#pragma once
#include "core.h"
#include <algorithm>
#include <cmath>
#include <limits>

namespace terraforest::experimental {
enum class RayStatus {hit,miss,work_limit,cancelled,invalid_input};
struct RayControl {size_t max_cells=4096;bool(*cancel)(void*)=nullptr;void*context=nullptr;};
struct DensityHit {RayStatus status=RayStatus::miss;double fraction=0;V3 position{};size_t cells=0;};
inline double polynomial(const double*c,double t){return ((c[3]*t+c[2])*t+c[1])*t+c[0];}
// Partition at derivative roots so same-sign endpoints cannot hide two roots.
// Numerical zero tolerance is relative to coefficient magnitude, not world units.
inline bool first_cubic_root(const double*c,double&root){
 double scale=0;for(int i=0;i<4;i++)scale=std::max(scale,std::abs(c[i]));
 if(scale==0){root=0;return true;}
 double normalized[4];for(int i=0;i<4;i++)normalized[i]=c[i]/scale;c=normalized;
 double eps=64*std::numeric_limits<double>::epsilon();
 double cuts[4]={0,1,0,0};int count=2;
 auto add=[&](double t){if(t>0&&t<1)cuts[count++]=t;};
 double a=3*c[3],b=2*c[2],d=c[1];
 if(std::abs(a)<=eps){if(std::abs(b)>eps)add(-d/b);}
 else{
  double disc=b*b-4*a*d;
  if(disc>=0){double q=-.5*(b+std::copysign(std::sqrt(disc),b));if(q!=0){add(q/a);add(d/q);}else add(-b/(2*a));}
 }
 std::sort(cuts,cuts+count);
 for(int i=0;i<count;i++){
  double lo=cuts[i],fl=polynomial(c,lo);
  if(std::abs(fl)<=eps){root=lo;return true;}
  if(i+1==count)break;
  double hi=cuts[i+1],fh=polynomial(c,hi);
  if((fl<0)==(fh<0))continue;
  for(int j=0;j<60;j++){double mid=(lo+hi)*.5,fm=polynomial(c,mid);if(fm==0){lo=hi=mid;break;}if((fm<0)==(fl<0)){lo=mid;fl=fm;}else hi=mid;}
  root=(lo+hi)*.5;return true;
 }
 return false;
}
// First surface root, including exits from solid. A start on the surface hits at
// zero. The caller supplies immutable lattice samples; no allocations are used.
template<class Sample>
static DensityHit trace_density(V3 from,V3 to,Sample&&sample,const RayControl&control=RayControl{}){
 DensityHit out;double start[3]={from.x,from.y,from.z},delta[3]={double(to.x)-from.x,double(to.y)-from.y,double(to.z)-from.z};
 int bounds[3]={WORLD,WORLD_Y,WORLD};double enter=0,leave=1;
 bool moving=false;
 for(int k=0;k<3;k++)if(!std::isfinite(start[k])||!std::isfinite(delta[k])||std::abs(start[k])>10000||std::abs(start[k]+delta[k])>10000){out.status=RayStatus::invalid_input;return out;}
 for(int k=0;k<3;k++){
  moving|=delta[k]!=0;
  if(delta[k]==0){if(start[k]<0||start[k]>bounds[k])return out;}
  else{double a=-start[k]/delta[k],b=(bounds[k]-start[k])/delta[k];if(a>b)std::swap(a,b);enter=std::max(enter,a);leave=std::min(leave,b);}
 }
 if(!moving){out.status=RayStatus::invalid_input;return out;}
 if(enter>leave)return out;
 int cell[3];double next[3];
 for(int k=0;k<3;k++){
  double p=start[k]+delta[k]*enter;
  cell[k]=int(std::floor(p));if(delta[k]<0&&p==cell[k])cell[k]--;
  cell[k]=std::max(0,std::min(bounds[k]-1,cell[k]));
  next[k]=delta[k]==0?std::numeric_limits<double>::infinity():(cell[k]+(delta[k]>0?1:0)-start[k])/delta[k];
 }
 while(true){
  if(control.cancel&&control.cancel(control.context)){out.status=RayStatus::cancelled;return out;}
  if(out.cells>=control.max_cells){out.status=RayStatus::work_limit;return out;}out.cells++;
  double exit=std::min(leave,std::min(next[0],std::min(next[1],next[2])));
  if(exit<enter){out.status=RayStatus::invalid_input;return out;}
  double coefficient[4]={};
  for(int corner=0;corner<8;corner++){
   double value=sample(cell[0]+(corner&1),cell[1]+((corner>>1)&1),cell[2]+((corner>>2)&1));
   if(!std::isfinite(value)){out.status=RayStatus::invalid_input;return out;}
   double product[4]={value,0,0,0};
   for(int k=0;k<3;k++){
    double p=start[k]+delta[k]*enter-cell[k],v=delta[k]*(exit-enter);
    if(!(corner&(1<<k))){p=1-p;v=-v;}
    for(int j=k+1;j>=0;j--)product[j]=product[j]*p+(j?product[j-1]*v:0);
   }
   for(int j=0;j<4;j++)coefficient[j]+=product[j];
  }
  for(double c:coefficient)if(!std::isfinite(c)){out.status=RayStatus::invalid_input;return out;}
  double local;
  if(first_cubic_root(coefficient,local)){
   if(control.cancel&&control.cancel(control.context)){out.status=RayStatus::cancelled;return out;}
   out.status=RayStatus::hit;out.fraction=enter+(exit-enter)*local;
   out.position={float(start[0]+delta[0]*out.fraction),float(start[1]+delta[1]*out.fraction),float(start[2]+delta[2]*out.fraction)};return out;
  }
  if(exit==leave)return out;
  for(int k=0;k<3;k++)if(next[k]<=exit){cell[k]+=delta[k]>0?1:-1;if(cell[k]<0||cell[k]>=bounds[k])return out;next[k]=(cell[k]+(delta[k]>0?1:0)-start[k])/delta[k];}
  enter=exit;
 }
}
static DensityHit trace_world_density(const World&w,V3 from,V3 to,const RayControl&control=RayControl{}){
 if(!w.edit_columns){DensityHit invalid;invalid.status=RayStatus::invalid_input;return invalid;}
 return trace_density(from,to,[&](int x,int y,int z){float value=clampf(w.sample(x,y,z),-SDF_BAND,SDF_BAND)*SDF_SCALE;return double(int(value>=0?value+.5f:value-.5f))/SDF_SCALE;},control);
}
} // namespace terraforest::experimental
