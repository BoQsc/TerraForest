#include "road_profile.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

namespace terraforest {
using namespace godot;
namespace {
using Cubic=std::array<double,4>;
double height(const Cubic &curve,double position){return ((curve[0]*position+curve[1])*position+curve[2])*position+curve[3];}
double slope(const Cubic &curve,double position){return (3*curve[0]*position+2*curve[1])*position+curve[2];}
double smooth(double value){value=std::clamp(value,0.,1.);return value*value*(3-2*value);}
double derivative(double value){return value>0&&value<1?6*value*(1-value):0;}
std::array<double,2> height_range(const Cubic &curve){
 std::array<double,2> range{std::min(height(curve,0),height(curve,1)),std::max(height(curve,0),height(curve,1))};
 auto inspect=[&](double position){if(position>0&&position<1){range[0]=std::min(range[0],height(curve,position));range[1]=std::max(range[1],height(curve,position));}};
 double discriminant=4*curve[1]*curve[1]-12*curve[0]*curve[2];
 if(std::abs(curve[0])>1e-14&&discriminant>=0)for(double sign:{-1.,1.})inspect((-2*curve[1]+sign*std::sqrt(discriminant))/(6*curve[0]));
 else if(std::abs(curve[1])>1e-14)inspect(-curve[2]/(2*curve[1]));
 return range;
}
std::array<double,2> slope_range(const Cubic &curve){
 std::array<double,2> range{std::min(slope(curve,0),slope(curve,1)),std::max(slope(curve,0),slope(curve,1))};
 if(std::abs(curve[0])>1e-14){double position=-curve[1]/(3*curve[0]);if(position>0&&position<1){range[0]=std::min(range[0],slope(curve,position));range[1]=std::max(range[1],slope(curve,position));}}
 return range;
}
double magnitude(const std::array<double,2> &range){return std::max(std::abs(range[0]),std::abs(range[1]));}
double curvature(const Cubic &curve){return std::max(std::abs(2*curve[1]),std::abs(6*curve[0]+2*curve[1]));}
Cubic interval(const Cubic &curve,double start,double span){return {curve[0]*span*span*span,(3*curve[0]*start+curve[1])*span*span,slope(curve,start)*span,height(curve,start)};}
Dictionary invalid(){Dictionary result;result["ok"]=false;result["reason"]="Invalid road burial trial profile";return result;}
}
Dictionary NativeRoadProfile::burial_trial(const PackedFloat64Array &coefficients,double spacing) const {
 if(coefficients.is_empty()||coefficients.size()%4||coefficients.size()>256||!std::isfinite(spacing)||spacing<1||spacing>256)return invalid();
 int count=coefficients.size()/4;
 std::vector<Cubic> original(count);
 double original_grade=0;bool ascending=true,descending=true;
 for(int section=0;section<count;++section){
  for(int component=0;component<4;++component){double value=coefficients[section*4+component];if(!std::isfinite(value)||std::abs(value)>4096)return invalid();original[section][component]=value;}
  auto range=slope_range(original[section]);original_grade=std::max(original_grade,magnitude(range)/spacing);
  ascending=ascending&&range[0]>=-1e-9;descending=descending&&range[1]<=1e-9;
  if(section>0&&(std::abs(height(original[section-1],1)-height(original[section],0))>1e-4||std::abs(slope(original[section-1],1)-slope(original[section],0))>1e-3))return invalid();
 }
 int subdivisions=std::min({64/count,std::max(1,int(std::floor(spacing))),std::max(1,int(std::ceil(spacing/1.5)))});
 double step=spacing/subdivisions,length=spacing*count,taper=std::min(12.,length*.5);
 auto evaluate=[&](int section,double position){
  double base=height(original[section],position),grade=slope(original[section],position)/spacing;
  double phase=base-std::floor(base),rise=(phase-.30)/.30,fall=(.95-phase)/.35;
  double cut=.18*smooth(rise)*smooth(fall);
  double cut_gradient=.18*(derivative(rise)*smooth(fall)/.30-smooth(rise)*derivative(fall)/.35);
  double distance=(section+position)*spacing,near=distance/taper,far=(length-distance)/taper;
  double blend=smooth(near)*smooth(far);
  double blend_gradient=(derivative(near)*smooth(far)-smooth(near)*derivative(far))/taper;
  return std::array<double,2>{cut*blend,cut_gradient*grade*blend+cut*blend_gradient};
 };
 std::vector<Cubic> baseline,proposal;
 std::vector<double> cuts,gradients;
 for(int section=0;section<count;++section)for(int part=0;part<subdivisions;++part){
  double start=double(part)/subdivisions;auto point=evaluate(section,start);
  cuts.push_back(point[0]);gradients.push_back(point[1]);
  baseline.push_back(interval(original[section],start,1./subdivisions));
 }
 cuts.push_back(0);gradients.push_back(0);gradients[0]=0;
 auto desired=cuts;
 int radius=std::min(16,int(std::ceil(6./step)));
 for(size_t node=0;node<cuts.size();++node){
  int part=int(node)%subdivisions,section=int(node)/subdivisions;
  if(part==0||magnitude(slope_range(original[section]))/spacing<.005){cuts[node]=0;continue;}
  double total=0,weights=0;
  for(int offset=-radius;offset<=radius;++offset){
   int neighbor=int(node)+offset;
   if(neighbor<section*subdivisions||neighbor>(section+1)*subdivisions)continue;
   double weight=std::exp(-.5*std::pow(offset*step/3.,2));total+=desired[neighbor]*weight;weights+=weight;
  }
  double distance=part*step,fade=std::min(8.,spacing*.5);
  cuts[node]=total/weights*smooth(distance/fade)*smooth((spacing-distance)/fade);
 }
 for(size_t node=1;node+1<cuts.size();++node){
  double before=(cuts[node]-cuts[node-1])/step,after=(cuts[node+1]-cuts[node])/step;
  gradients[node]=(before+after)*.5;
  if(before*after<=0||gradients[node]*before<=0)gradients[node]=0;
  else gradients[node]=std::copysign(std::min(std::abs(gradients[node]),1.5*std::min(std::abs(before),std::abs(after))),before);
 }
 for(size_t section=0;section<baseline.size();++section){
  double delta=cuts[section+1]-cuts[section],first=gradients[section]*step,last=gradients[section+1]*step;
  Cubic cut{-2*delta+first+last,3*delta-2*first-last,first,cuts[section]},revised{};
  for(int component=0;component<4;++component)revised[component]=baseline[section][component]-cut[component];
  proposal.push_back(revised);
 }
 auto metrics=[&](double weight){
  std::array<double,6> result{};
  for(size_t section=0;section<baseline.size();++section){
   Cubic blended{},difference{};
   for(int component=0;component<4;++component){difference[component]=(proposal[section][component]-baseline[section][component])*weight;blended[component]=baseline[section][component]+difference[component];}
   auto displacement=height_range(difference),grades=slope_range(blended);
   result[0]=std::max(result[0],magnitude(grades)/step);
   result[1]=std::max(result[1],-displacement[0]);
   result[2]=std::max(result[2],displacement[1]);
   result[3]=std::max(result[3],magnitude(slope_range(difference))/step);
   result[4]=std::max(result[4],curvature(difference)/(step*step));
   if(ascending)result[5]=std::max(result[5],-grades[0]/step);
   if(descending)result[5]=std::max(result[5],grades[1]/step);
  }
  return result;
 };
 double weight=0;
 if(original_grade>=.005&&original_grade<=.16&&step<=4){
  double low=0,high=1;
  for(int iteration=0;iteration<32;++iteration){
   double candidate=(low+high)*.5;auto limits=metrics(candidate);
   if(limits[0]<=.16&&limits[1]<=.18&&limits[2]<=1e-7&&limits[3]<=.025&&limits[4]<=.010&&limits[5]<=1e-7)low=candidate;else high=candidate;
  }
  weight=low;
 }
 PackedFloat64Array result_coefficients;
 if(weight<.01){weight=0;subdivisions=1;result_coefficients=coefficients;}
 else for(size_t section=0;section<baseline.size();++section)for(int component=0;component<4;++component)result_coefficients.push_back(baseline[section][component]+weight*(proposal[section][component]-baseline[section][component]));
 auto limits=metrics(weight);
 Dictionary result;result["ok"]=true;result["coefficients"]=result_coefficients;result["subdivisions"]=subdivisions;result["weight"]=weight;
 result["max_grade"]=limits[0];result["max_shift"]=limits[1];result["max_raise"]=limits[2];result["max_grade_change"]=limits[3];result["max_curvature_change"]=limits[4];result["version"]=1;return result;
}
}
